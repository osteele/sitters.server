Q = require 'q'
util = require 'util'
Firebase = require 'firebase'

models = require './models'
findOneAccount = Q.nbind models.Account.findOne, models.Account
findOneUser = Q.nbind models.User.findOne, models.User
createAccount = Q.nbind models.Account.create, models.Account
createFamily = Q.nbind models.Family.create, models.Family
createUser = Q.nbind models.User.create, models.User
findFamily = Q.nbind models.Family.find, models.Family
findSitter = Q.nbind models.Sitter.find, models.Sitter
findUser = Q.nbind models.User.find, models.User

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

updateSitterList = (accountKey, fn) ->
  [provider_name, provider_user_id] = accountKey.split('/', 2)
  models.schema.adapter.query {text: SelectAccountUserFamilySQL, values: [provider_name, provider_user_id]}, (err, result) ->
    throw err if err
    return unless result.length
    {family_id, sitter_ids} = result[0]
    sitter_ids = JSON.parse(sitter_ids)
    sitter_ids = fn(sitter_ids)
    return unless sitter_ids
    models.schema.adapter.query {text: UpdateFamilySittersSQL, values: [family_id, JSON.stringify(sitter_ids)]}, (err, result) ->
      throw err if err
    familyFB.child(String(family_id)).child('sitter_ids').set sitter_ids

handlers =
  addSitter: (accountKey, {sitterId}) ->
    updateSitterList accountKey, (sitter_ids) ->
      return if sitterId in sitter_ids
      return sitter_ids.concat([sitterId])

  registerUser: (accountKey, {displayName, email}) ->
    [provider_name, provider_user_id] = accountKey.split('/', 2)
    findOneAccount(where: {provider_name, provider_user_id}).then((account) ->
      return if account
      findOneUser({email}).then((user) ->
        if user
          Q.ninvoke(user, 'updateAttributes', {displayName})
        else
          createUser {displayName, email}
      ).then((user) ->
        createAccountP = createAccount {provider_name, provider_user_id, user_id: user.id}
        createFamilyP = createFamily {sitter_ids: []}
        Q.all([createAccountP, createFamilyP]).spread (account, family) ->
          Q.ninvoke(user, 'updateAttributes', family_id: family.id).then -> Q(family)
      )
    ).then((family) ->
      return unless family
      Q.ninvoke(familyFB.child(String(family.id)), 'set', {sitter_ids: family.sitter_ids}).then ->
        Q.ninvoke accountFB.child(accountKey).child('family_id'), 'set', family.id
    ).done()

  setSitterCount: (accountKey, {count}) ->
    updateSitterList accountKey, (sitter_ids) ->
      count = Math.max(0, Math.min(7, count))
      return [1..count]
