_ = require 'underscore'
Q = require 'q'
util = require 'util'
Firebase = require 'firebase'
models = require './lib/models'
_(global).extend(require('./lib/modelsP'))
_(global).extend(require('./lib/push'))

DefaultSitterConfirmationDelay = 20 * 1000

rootFB = new Firebase('https://sevensitters.firebaseIO.com/')
requestsFB = rootFB.child('request')
messagesFB = rootFB.child('message')
familyFB = rootFB.child('family')
accountFB = rootFB.child('account')

console.log "Polling #{requestsFB}"
requestsFB.on 'child_added', (snapshot) ->
  key = snapshot.name()
  message = snapshot.val()
  {accountKey, requestType, parameters} = message
  console.log "Processing request #{requestType} from #{accountKey} with #{JSON.stringify(parameters).replace(/"(\w+)":/g, '$1:')}"
  try
    handleRequestFrom accountKey, requestType, parameters
  catch err
    console.error err
  finally
    requestsFB.child(key).remove()

handleRequestFrom = (accountKey, requestType, parameters) ->
  handler = handlers[requestType]
  console.error "Unknown request type #{requestType}" unless handler
  promise = handler(accountKey, parameters)
  # delay ?= DefaultAddSitterDelay
  # promise = Q.delay(delay).then(promise) if delay
  promise.done()

# Message is expected to have:
#   messageType: String -- client keys behavior off of this
#   messageTitle: String -- UIAlert title
#   messageText: String -- UIAlert text; also, push notification text
#   parameters: Hash -- client interprets message against this
sendMessageTo = (accountKey, message) ->
  console.log "Send #{util.inspect(message)} -> #{accountKey}"
  firebaseMessageId = messagesFB.child(accountKey).push message
  # console.log "firebaseMessageId = #{firebaseMessageId}"
  [provider_name, provider_user_id] = accountKey.split('/', 2)
  queryP(text: SelectDeviceTokenFromAccountKeySQL, values: [provider_name, provider_user_id]).then (rows) ->
    rows.forEach ({token}) ->
      console.log "  Push #{message.messageType} -> #{token}"
      pushMessageTo token, alert: message.messageText, payload: message

SelectDeviceTokenFromAccountKeySQL = """
SELECT token
FROM devices
JOIN users ON users.id=devices.user_id
JOIN accounts ON accounts.user_id=users.id
WHERE provider_name=$1 and provider_user_id=$2;"""

SelectAccountUserFamilySQL = """
SELECT families.id AS family_id, sitter_ids
FROM families
JOIN users ON families.id=family_id
JOIN accounts ON users.id=user_id
WHERE provider_name=$1 and provider_user_id=$2;"""

UpdateFamilySittersSQL = "UPDATE families SET sitter_ids=$2 WHERE id=$1;"

updateSitterListP = (accountKey, fn) ->
  [provider_name, provider_user_id] = accountKey.split('/', 2)
  queryP(text: SelectAccountUserFamilySQL, values: [provider_name, provider_user_id]).then (rows) ->
    {family_id, sitter_ids} = rows[0]
    sitter_ids = JSON.parse(sitter_ids)
    sitter_ids = fn(sitter_ids)
    return Q(false) unless sitter_ids
    console.log "Update sitter_ids <- #{sitter_ids}"
    queryP(text: UpdateFamilySittersSQL, values: [family_id, JSON.stringify(sitter_ids)]).then ->
      console.log "Updated sitter_ids <- #{sitter_ids}"
      familyFB.child(String(family_id)).child('sitter_ids').set sitter_ids
      Q(true)

handlers =
  addSitter: (accountKey, {sitterId}) ->
    updateSitterListP(accountKey, (sitter_ids) ->
      console.log "Add sitter #{sitterId} to #{sitter_ids}"
      return if sitterId in sitter_ids
      return sitter_ids.concat([sitterId])
    ).then((modified) ->
      console.log "Didn't modify sitter id list"
      return unless modified
      console.log "Added sitter id=#{sitterId}"
      findSitterP(sitterId)
    ).then((sitter) ->
      # console.log "Couldn't find sitter id=#{sitterId}" unless sitter
      return unless sitter
      console.log "Sending message add sitter #{sitter.id}"
      sitterFirstName = sitter.data.name.split(/\s/).shift()
      sendMessageTo accountKey,
        messageType: 'sitterAcceptedConnection'
        messageTitle: 'Sitter Confirmed'
        messageText: "#{sitterFirstName} has accepted your request. We’ve added her to your Seven Sitters."
        parameters: {sitterId: sitterId}
    )

  registerDeviceToken: (accountKey, {token}) ->
    [provider_name, provider_user_id] = accountKey.split('/', 2)
    accountP = findOneAccountP where: {provider_name, provider_user_id}
    deviceP = findOneDeviceP where: {token}
    Q.all([accountP, deviceP]).spread((account, device) ->
      console.log "Register #{token} for device=#{device} account=#{account}"
      return unless account
      return if device and account.user_id == device.user_id
      if device
        console.log "Update device #{device}"
        updateAttributesP device, user_id: account.user_id
      else
        console.log "Create device"
        createDeviceP {token, user_id: account.user_id}
    )

  registerUser: (accountKey, {displayName, email}) ->
    [provider_name, provider_user_id] = accountKey.split('/', 2)
    findOneAccountP(where: {provider_name, provider_user_id}).then((account) ->
      console.log "Found account key=#{accountKey}" if account
      return if account
      console.log "Creating account key=#{accountKey}" if account
      findOneUserP({email}).then((user) ->
        if user
          console.log "Found user email=#{email}"
          updateAttributes user, {displayName}
        else
          console.log "Creating user email=#{email}"
          createUserP {displayName, email}
      ).then((user) ->
        accountP = createAccountP {provider_name, provider_user_id, user_id: user.id}
        familyP = createFamilyP {sitter_ids: []}
        Q.all([accountP, familyP]).spread (account, family) ->
          updateAttributes(user, family_id: family.id).then ->
            Q(family)
      )
    ).then((family) ->
      return unless family
      Q.ninvoke(familyFB.child(String(family.id)), 'set', {sitter_ids: family.sitter_ids}).then ->
        Q.ninvoke accountFB.child(accountKey).child('family_id'), 'set', family.id
    )

  reserveSitter: (accountKey, {sitterId, startTime, endTime}) ->
    startTime = new Date(startTime)
    endTime = new Date(endTime)
    console.log "Finding sitter #{sitterId}"
    findOneSitterP(where: {sitter_id: sitterId}).then((sitter) ->
      console.log "findOneSitterP(#{sitterId}) = #{sitter}"
      return unless sitter
      sitterFirstName = sitter.data.name.split(/\s/).shift()
      console.log "and #{sitter}"
      sendMessageTo accountKey,
        messageType: 'sitterConfirmedReservation'
        messageTitle: 'Sitter Confirmed'
        messageText: "#{sitterFirstName} has confirmed your request."
        parameters: {sitterId: sitterId, startTime: startTime.toISOString(), endTime: endTime.toISOString()}
    )

  setSitterCount: (accountKey, {count}) ->
    updateSitterListP accountKey, (sitter_ids) ->
      count = Math.max(0, Math.min(7, count))
      return if sitter_ids.length == count
      return _.uniq(sitter_ids.concat([1..7]))[0...count]
