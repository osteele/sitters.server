Q = require 'Q'
_ = require 'underscore'
_(global).extend require('../lib/models')
_(global).extend require('../lib/firebase')

ModelClassesByName = {accounts: Account, families: Family, sitters: Sitter, users: User}

UpdateFunctions =
  accounts: (account) ->
    account.getUser().then (user) ->
      fb = accountsFB.child(account.firebaseKey).child('family_id')
      fbOnceP(fb).then (snapshot) ->
        unless snapshot.val() == user.family_id
          fbSetP fb, user.family_id

  sitters: (sitter) ->
    fb = sittersFB.child(sitter.id)
    fbSetP fb, sitter.data

  families: (family) ->
    console.info 'family', family.id

  users: (user) ->
    console.info 'user', user.id

exports.updateSomeP = (limit=10) ->
  sequelize.query("SELECT DISTINCT table_name, entity_id FROM change_log LIMIT :limit", null, {raw:true}, {limit}).then (rows) ->
    Q.all(rows.map ({operation, table_name, entity_id}) ->
      tableClass = ModelClassesByName[table_name]
      tableClass.find(entity_id).then((entity) ->
        console.info 'Update', table_name, '#' + entity_id
        UpdateFunctions[table_name]?(entity)
      ).then ->
        sequelize.query("DELETE FROM change_log WHERE table_name=:table_name AND entity_id=:entity_id", null, {raw:true}, {table_name, entity_id})
    ).get('length')

exports.updateAllP = (trancheSize=10, total=0) ->
  exports.updateSomeP(trancheSize).then (count) ->
    total += count
    if count > 0
      exports.updateAllP(trancheSize, total)
    else
      Q(total)
