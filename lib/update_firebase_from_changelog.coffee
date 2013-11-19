Q = require 'Q'
_ = require 'underscore'
_(global).extend require('../lib/models')
_(global).extend require('../lib/firebase')

winston = require 'winston'
winston.loggers.add 'firebase', console: {colorize: true, label: 'firebase'}
logger = winston.loggers.get('firebase')

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
    data = _.extend {id:String(sitter.id)}, sitter.data
    fbSetP fb, data

  families: (family) ->
    familiesFB.child(String(family.id)).child('sitter_ids').set family.sitter_ids

  users: (user) ->
    user.getAccounts().then (accounts) ->
      Q.all accounts.map UpdateFunctions.accounts

exports.updateSomeP = (limit=10) ->
  sequelize.query("SELECT DISTINCT table_name, entity_id FROM change_log LIMIT :limit", null, {raw:true}, {limit}).then (rows) ->
    Q.all(rows.map ({operation, table_name, entity_id}) ->
      tableClass = ModelClassesByName[table_name]
      tableClass.find(entity_id).then((entity) ->
        logger.info 'Update', table_name, '#' + entity_id
        UpdateFunctions[table_name]?(entity)
      ).then ->
        sequelize.query("DELETE FROM change_log WHERE table_name=:table_name AND entity_id=:entity_id", null, {raw:true}, {table_name, entity_id})
    ).get('length')

exports.updateAllP = (trancheSize=10, total=0) ->
  exports.updateSomeP(trancheSize).then (count) ->
    total += count
    return total
    if count > 0
      exports.updateAllP(trancheSize, total)
    else
      Q total
