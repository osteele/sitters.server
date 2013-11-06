Q = require 'q'
util = require 'util'
Firebase = require 'firebase'

DefaultAddSitterDelay = 20 * 1000

models = require './models'
findOneAccountP = Q.nbind models.Account.findOne, models.Account
findOneUserP = Q.nbind models.User.findOne, models.User
createAccountP = Q.nbind models.Account.create, models.Account
createFamilyP = Q.nbind models.Family.create, models.Family
createUserP = Q.nbind models.User.create, models.User
findFamilyP = Q.nbind models.Family.find, models.Family
findSitterP = Q.nbind models.Sitter.find, models.Sitter
findUserP = Q.nbind models.User.find, models.User

rootFB = new Firebase('https://sevensitters.firebaseIO.com/')
requestsFB = rootFB.child('request')
messagesFB = rootFB.child('message')
familyFB = rootFB.child('family')
accountFB = rootFB.child('account')

requestsFB.on 'child_added', (snapshot) ->
  key = snapshot.name()
  message = snapshot.val()
  {accountKey, requestType, parameters} = message
  console.log "Request", requestType, 'from', accountKey, 'with', JSON.stringify(parameters).replace(/"(\w+)":/g, '$1:')
  try
    handleRequestFrom accountKey, requestType, parameters
  catch err
    console.error err
  finally
    requestsFB.child(key).remove()

handleRequestFrom = (accountKey, requestType, parameters) ->
  handler = handlers[requestType]
  console.error "Unknown request type #{requestType}" unless handler
  handler?(accountKey, parameters)

sendMessageTo = (accountKey, message) ->
  console.log "Send #{util.inspect(message)} -> #{accountKey}"
  messagesFB.child(accountKey).push message

SelectAccountUserFamilySQL = """
SELECT families.id AS family_id, sitter_ids
FROM families
JOIN users ON families.id=family_id
JOIN accounts ON users.id=user_id
WHERE provider_name=$1 and provider_user_id=$2;"""

UpdateFamilySittersSQL = "UPDATE families SET sitter_ids=$2 WHERE id=$1;"

queryP = Q.nbind models.schema.adapter.query, models.schema.adapter

updateSitterListP = (accountKey, fn) ->
  [provider_name, provider_user_id] = accountKey.split('/', 2)
  queryP(text: SelectAccountUserFamilySQL, values: [provider_name, provider_user_id]).then (rows) ->
    {family_id, sitter_ids} = rows[0]
    sitter_ids = JSON.parse(sitter_ids)
    sitter_ids = fn(sitter_ids)
    return Q(false) unless sitter_ids
    console.log "Update sitter_ids<-#{sitter_ids}"
    queryP(text: UpdateFamilySittersSQL, values: [family_id, JSON.stringify(sitter_ids)]).then ->
      console.log "Updated sitter_ids<-#{sitter_ids}"
      familyFB.child(String(family_id)).child('sitter_ids').set sitter_ids
      Q(true)

handlers =
  addSitter: (accountKey, {sitterId, delay}) ->
    delay ?= DefaultAddSitterDelay
    Q.delay(delay).then(->
      updateSitterListP accountKey, (sitter_ids) ->
        console.log "Add sitter #{sitterId} to #{sitter_ids}"
        return if sitterId in sitter_ids
        return sitter_ids.concat([sitterId])
    ).then((added) ->
      console.log "Added=#{added}; find sitter id=#{sitterId}"
      findSitterP(sitterId) if added
    ).then((sitter) ->
      console.log "Couldn't find sitter id=#{sitterId}"
      return unless sitter
      console.log "Sending message add sitter #{sitter.id}"
      sitterFirstName = sitter.data.name.split(/\s/).shift()
      sendMessageTo accountKey,
        messageTitle: 'Sitter Confirmed'
        messageText: "#{sitterFirstName} has accepted your request. We’ve added her to your Seven Sitters."
    ).done()

  registerUser: (accountKey, {displayName, email}) ->
    [provider_name, provider_user_id] = accountKey.split('/', 2)
    findOneAccountP(where: {provider_name, provider_user_id}).then((account) ->
      console.log "Found account key=#{accountKey}" if account
      return if account
      console.log "Creating account key=#{accountKey}" if account
      findOneUserP({email}).then((user) ->
        if user
          console.log "Found user email=#{email}"
          Q.ninvoke(user, 'updateAttributes', {displayName})
        else
          console.log "Creating user email=#{email}"
          createUserP {displayName, email}
      ).then((user) ->
        accountP = createAccountP {provider_name, provider_user_id, user_id: user.id}
        familyP = createFamilyP {sitter_ids: []}
        Q.all([accountP, familyP]).spread (account, family) ->
          Q.ninvoke(user, 'updateAttributes', family_id: family.id).then -> Q(family)
      )
    ).then((family) ->
      return unless family
      Q.ninvoke(familyFB.child(String(family.id)), 'set', {sitter_ids: family.sitter_ids}).then ->
        Q.ninvoke accountFB.child(accountKey).child('family_id'), 'set', family.id
    ).done()

  setSitterCount: (accountKey, {count}) ->
    updateSitterListP accountKey, (sitter_ids) ->
      count = Math.max(0, Math.min(7, count))
      return [] unless count > 0
      return [1..count]
