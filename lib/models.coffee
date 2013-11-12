require('dotenv').load()

Sequelize = require('sequelize-postgres').sequelize
sequelize = new Sequelize(process.env.DATABASE_URL, {
  dialect: 'postgres',
  define: {underscored:true}
})

Account = sequelize.define 'accounts',
  provider_name: {type: Sequelize.STRING, index: true}
  provider_user_id: {type: Sequelize.STRING, index: true}

Device = sequelize.define 'devices',
  token: {type: Sequelize.STRING, index: true, unique: true}

Family = sequelize.define 'families',
  sitter_ids: Sequelize.ARRAY(Sequelize.INTEGER)

Sitter = sequelize.define 'sitters',
  data: Sequelize.TEXT

User = sequelize.define 'users',
  displayName: Sequelize.STRING
  email: {type: Sequelize.STRING, index: true, unique: true}

Family.hasMany User
User.hasMany Account
User.hasMany Device
# migration.addIndex('Person', ['firstname', 'lastname'])

sequelize.sync()

module.exports = {
  Account
  Device
  Family
  Sitter
  User
  sequelize
}
