# require 'dotenv'
# console.log process.env.FIREBASE_SECRET

Q = require 'q'
util = require 'util'
Firebase = require 'firebase'

models = require './models'
findAllAccounts = Q.nbind models.Account.all, models.Account
findAllUsers = Q.nbind models.User.all, models.User
createAccount = Q.nbind models.Account.create, models.Account
createFamily = Q.nbind models.Family.create, models.Family
createUser = Q.nbind models.User.create, models.User
findFamily = Q.nbind models.Family.find, models.Family
findSitter = Q.nbind models.Sitter.find, models.Sitter
findUser = Q.nbind models.User.find, models.User

rootFB = new Firebase('https://sevensitters.firebaseIO.com/')
requestsFB = rootFB.child('request')
messagesFB = rootFB.child('message')
erroredFB = rootFB.child('errored')
familyFB = rootFB.child('family')
accountFB = rootFB.child('account')

requestsFB.on 'child_added', (snapshot) ->
  key = snapshot.name()
  message = snapshot.val()
  console.log "Request #{util.inspect(message)}"
  try
    handleRequestFrom message.accountKey, message.requestType, message.parameters
  catch e
    erroredFB << message
  requestsFB.child(key).remove()

handleRequestFrom = (accountKey, requestType, parameters) ->
  handler = handlers[requestType]
  console.error "Unknown request type #{requestType}" unless handler
  handler?(accountKey, parameters)

sendMessageTo = (accountKey, message) ->
  console.log "Send #{util.inspect(message)} -> #{accountKey}"
  messagesFB.child(accountKey).push message

handlers =
  addSitter: (accountKey, {familyId, sitterId}) ->
    # family = findFamily familyId
    # sitter = findSitter sitterId
    # Q.all([family, sitter]).spread( (family, sitter) ->
    #   console.log 'family', familyId, family
    #   console.log 'sitter', sitterId, sitter #.data.name
    # ).done (->console.log 'fulfilled'), (->console.log 'rejected'), (->console.log 'progress')
    models.Family.find familyId, (error, family) ->
      console.log 'family', familyId, family
      models.Sitter.find sitterId, (error, sitter) ->
        console.log 'sitter', sitterId, sitter.data.name
    return
    process.exit()

    sitterIdsRef = rootFB.child("family/#{familyId}/sitter_ids")

    sitterIdsRef.once 'value', (snapshot) ->
      sitterIds = snapshot.val()
      return if sitterId in sitterIds
      sitterIdsRef.set sitterIds.concat([sitterId])
      sendMessageTo accountKey,
        messageType: 'addedSitter',
        messageTitle: 'Sitter Confirmed',
        messageText:'{{sitter.firstName}} has accepted your request. We’ve added her to your Seven Sitters.',
        parameters: {sitterId}

    # sitterIdsRef.transaction (sitterIds) ->
    #   return if sitterId in sitterIds
    #   return sitterIds.concat([sitterId])
    # , (error, committed, snapshot) ->
    #   messagesFB.child(accountKey).push messageType: 'addedSitter', sitterId: sitterId

  registerUser: (accountKey, {displayName, email}) ->
    [provider, provider_user_id] = accountKey.split('/', 2)
    findAllAccounts(where: {provider, provider_user_id}, limit:1).then (accounts) ->
      return if accounts.length
      findAllUsers({email}).then((users) ->
        if users.length
          user = users[0]
          Q.ninvoke(user, 'updateAttributes', {displayName}).then(null)
        else
          createUser({displayName, email})
      ).then((user) ->
        createAccountP = createAccount {provider, provider_user_id, user_id: user.id}
        createFamilyP = createFamily {sitter_ids: []}
        Q.all([createAccountP, createFamilyP]).spread (account, family) ->
          Q.ninvoke(user, 'updateAttributes', family_id: family.id).then -> Q(family)
      )
    .then((family) ->
      # new account, family
      return unless family
      Q.ninvoke(familyFB.child(String(family.id)), 'set', {sitter_ids: family.sitter_ids}).then ->
        console.log 'then', arguments
        Q.ninvoke accountFB.child(accountKey).child('family_id'), 'set', family.id
    )
    .done()
