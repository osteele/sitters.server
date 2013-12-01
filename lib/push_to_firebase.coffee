Q = require 'q'
_ = require 'underscore'
require('../lib/utils')
_(global).extend require('../lib/models')
_(global).extend require('../lib/firebase')

winston = require 'winston'
logger = winston.loggers.add 'firebase-push', console: {colorize: true, label: '→firebase'}

ModelClassesByName = {}.tap (dict) ->
  models = [Account, Family, PaymentCustomer, Sitter, User]
  models.forEach (model) =>
    this[model.tableName] = model

getUserFB = (account) ->
  UserFB.child('auth').child(account.firebaseKey)

UpdateFunctions =
  accounts: (account) ->
    account.getUser().then (user) ->
      fb = getUserFB(account).child('family_id')
      fbOnceP(fb).then (snapshot) ->
        unless snapshot.val() == user.family_id
          fbSetP fb, user.family_id

  families: (family) ->
    fbSetP FamilyFB.child(String(family.id)).child('sitter_ids'), family.sitter_ids

  payment_customers: (paymentCustomer) ->
    paymentCustomer.getUser().then((user) ->
      logger.info "→ User ##{user?.id}"
      user.getAccounts()
    ).then((accounts) ->
      Q.all accounts.map (account) ->
        logger.info "→ Account ##{account.id}"
        fbSetP getUserFB(account).child('cardInfo'), paymentCustomer.card_info
    )

  sitters: (sitter) ->
    fb = SitterFB.child(sitter.id)
    data = _.extend {id:String(sitter.id)}, sitter.data
    fbSetP fb, data

  users: (user) ->
    user.getAccounts().then (accounts) ->
      Q.all accounts.map UpdateFunctions.accounts

exports.updateSomeP = (limit=10) ->
  sequelize.query("SELECT DISTINCT table_name, entity_id FROM change_log LIMIT :limit", null, {raw:true}, {limit}).then (rows) ->
    Q.all(rows.map ({operation, table_name, entity_id}) ->
      tableClass = ModelClassesByName[table_name]
      unless tableClass
        logger.warn "No update method for table #{table_name}"
        return
      tableClass.find(entity_id).then((entity) ->
        logger.info 'Deleted', table_name, '#' + entity_id unless entity
        return unless entity # TODO delete the fb record
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
