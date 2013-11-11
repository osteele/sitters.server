Q = require 'q'
models = require './models'

module.exports = {
  findOneAccountP: Q.nbind models.Account.findOne, models.Account
  findOneDeviceP: Q.nbind models.Device.findOne, models.Device
  findOneSitterP: Q.nbind models.Sitter.findOne, models.Sitter
  findOneUserP: Q.nbind models.User.findOne, models.User
  createAccountP: Q.nbind models.Account.create, models.Account
  createDeviceP: Q.nbind models.Device.create, models.Device
  createFamilyP: Q.nbind models.Family.create, models.Family
  createUserP: Q.nbind models.User.create, models.User
  findFamilyP: Q.nbind models.Family.find, models.Family
  findSitterP: Q.nbind models.Sitter.find, models.Sitter
  findUserP: Q.nbind models.User.find, models.User

  queryP: Q.nbind models.schema.adapter.query, models.schema.adapter
  updateAttributesP: (model, attrs) -> Q.invoke(model, 'updateAttributes', attrs)
}
