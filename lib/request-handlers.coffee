#
# Imports
# --

require('dotenv').load()
_ = require 'underscore'
Q = require 'q'

# Stripe handles payment card storage and payment processing.
stripe = require('stripe')(process.env.STRIPE_SECRET_KEY)

# Import the database models.
_(global).extend require('./models')


#
# Constants
# --

# How many seconds should a simulated sitter wait before responding to an invitation?
DefaultSitterConfirmationDelay = process.env.DEFAULT_SITTER_CONFIRMATION_DELAY || 20

# Maximum number of sitters attached to a family.
MaxSitterCount = 7


#
# Configure Logging
# --

Winston = require 'winston'
logger = Winston.loggers.add 'requests', console:{colorize:true, label:'requests'}


#
# Request Handlers
# --

SendClientMessage = require './messages'

module.exports =
  #
  # ### Add Sitter Invitation Flow
  #
  # * Parent -> server `addSitter` with sitter profile id
  # * Server creates record `Invitation(parentAddSitter)`
  # * Server -> sitter `inviteSitterToFamily` with parent id, invitiation id
  # * Sitter -> Server `acceptInvitation` with invitation id
  # * Server updates invitation.status = 'accepted'
  # * Server -> parent sitterAcceptedConnection -> with sitter profile id

  # #### Parent invites sitter
  #
  # The parent sends this to invite a sitter who is already in the system to join the parent's family sitters. `delay`
  # is used for development and debugging; it sets the amount of time that one of the simulated sitters will wait before
  # responding.
  addSitter: ({user:parent}, {sitterId:sitterProfileId, delay}) ->
    # TODO return if the sitter is already on the list
    invitationAttributes =
      type         : 'parentAddSitter'
      initiator_id : parent.id
      recipient_id : sitterProfileId
    Invitation.findOrCreate(invitationAttributes).then (invitation) ->
      console.info "Created invitation ##{invitation.id}" unless invitation.status
      if invitation.status == 'sent'
        console.info "Already sent invitation ##{invitation.id}"
        return
      SitterProfile.find(sitterProfileId)
      .then((sitter) -> sitter.getUser())
      .then((sitter) -> SendClientMessage.inviteSitterToFamily sitter, {invitation, parent, delay})
      .then(-> invitation.updateAttributes status:'sent')

  # #### Sitter accepts invitation
  #
  acceptInvitation: ({user:sitter}, {invitationId}) ->
    Invitation.find(invitationId).then (invitation) ->
      return unless invitation?.status == 'sent'
      # invitation.getInitiator().then (parent) ->
      User.find(invitation.initiator_id).then (parent) ->
        Q.all [
          invitation.updateAttributes status:'accepted'
          sitter.getSitterProfile().then (sitterProfile) ->
            updateUserSitterListP parent, (sitterProfileIds) ->
              logger.info "Adding sitter", sitterProfile.id, "to", sitterProfileIds
              return if sitterProfile.id in sitterProfileIds
              return sitterProfileIds.concat([sitterProfile.id])
          sitter.getSitterProfile().then (sitterProfile) ->
            SendClientMessage.sitterAcceptedConnection parent, {sitterProfile}
        ]

  # The client sends this when the user signs in, and on each launch if the user is already signed in. The server
  # creates or updates a Device record and associates it with the user, for use with mobile notifications.
  registerDeviceToken: ({user}, {deviceUuid:uuid, token}) ->
    user_id = user.id
    Device.find(where:{uuid})
    .then (device) ->
      logger.info "Register device #{uuid} for user ##{user.id}"
      if device
        return if device.user_id == user_id and device.token == token
        logger.info "Update device ##{device.id}"
        device.updateAttributes {token, user_id}
      else
        logger.info "Register device", {uuid, token, user_id}
        Device.create {uuid, token, user_id}

  # The client sends this when the user enters a payment card. THe server ensures the existence of a Stripe customer for
  # this user, and creates or replaces the payment card. The server also stores the card display information in the
  # database, for display in the client UI.
  registerPaymentToken: ({user}, {token, cardInfo}) ->
    PaymentCustomer.findOrCreate(user_id:user.id).then (customerRow) ->
      email = user.email
      metadata = {user_id:user.id}
      if customerRow?.stripe_customer_id
        logger.info "Found customer #{customerRow.stripe_customer_id}"
        stripe.customers.update(customerRow.stripe_customer_id, {card:token, email, metadata}).then ->
          customerRow.updateAttributes card_info:cardInfo
      else
        stripe.customers.create({card:token, email, metadata}).then (stripeCustomer) ->
          logger.info "New customer #{stripeCustomer.id}"
          attrs = {stripe_customer_id:stripeCustomer.id, card_info:cardInfo}
          PaymentCustomer.findOrCreate({user_id:user.id}, attrs).then (customerRow) ->
            customerRow.updateAttributes attrs

  # The client sends this when a user signs in, and on each launch if the user is already signed in. The server ensures
  # that a User record exists, associates it with the account that the user authenticated with, and ensures that a
  # Family for this user exists.
  registerUser: ({accountKey}, {displayName, email}) ->
    [provider_name, provider_user_id] = accountKey.split('-', 2)
    accountP = Account.findOrCreate {provider_name, provider_user_id}
    userP = User.findOrCreate {email}, {displayName}
    Q.all([accountP, userP]).spread (account, user) ->
      logger.info "Account key=#{accountKey}" if account
      logger.info "Update account #{account?.id} user_id=#{user?.id}"
      Q.all [
        account.updateAttributes user_id:user.id
        user.updateAttributes {displayName} #unless user.displayName == displayName,
        Family.find(user.family_id).then (family) ->
          return if family
          Family.create({sitter_ids: '{}'}).then (family) ->
            user.updateAttributes family_id:family.id
      ]

  # The client sends this when the user removes their payment card.
  removePaymentCard: ({user}, {}) ->
    PaymentCustomer.find(where: {user_id:user.id}).then (customerRow) ->
      stripeCustomerId = customerRow?.stripe_customer_id
      return unless stripeCustomerId
      removeCardInfo = -> customerRow.updateAttributes card_info:{}
      stripe.customers.retrieve(stripeCustomerId).then (customer) ->
        cardId = customer.cards.data[0]?.id
        if cardId
          stripe.customers.deleteCard(stripeCustomerId, cardId).then removeCardInfo
        else
          removeCardInfo()

  # The client sends this when the user requests a specific sitter for a specific time.
  # `delay` is used for development and debugging; it sets the amount of time that one
  # of the simulated sitters will wait before responding.
  reserveSitter: ({user}, {sitterId:sitterProfileId, startTime, endTime, delay}) ->
    delay ?= DefaultSitterConfirmationDelay
    startTime = new Date(startTime)
    endTime = new Date(endTime)
    logger.info "Waiting #{delay}s" if delay > 0
    Q.delay(delay * 1000).then(->
      SitterProfile.find(sitterProfileId)
    ).then((sitterProfile) ->
      logger.error "Unknown sitterProfile ##{sitterProfileId}" unless sitterProfile
      return unless sitterProfile
      SendClientMessage.sitterConfirmedReservation user, {sitterProfile, startTime, endTime}
    )

  #
  # ### Development and Debugging Requests
  #

  # This message is used for testing. It changes the number of sitters associated with the user's family, filling them
  # in as needed from the simulated sitters.
  setSitterCount: ({user}, {count}) ->
    updateUserSitterListP user, (sitter_ids) ->
      count = Math.max(0, Math.min(MaxSitterCount, count))
      return if sitter_ids.length == count
      return _.uniq(sitter_ids.concat([1..MaxSitterCount]))[0...count]

  # This message is used for testing, to test server error handling and reporting. It throws an error. If running in the
  # production environment, it only throws an error if the `DEBUG_SERVER` environment variable is set.
  simulateServerError: ->
    if process.env.NODE_ENV == 'production' and not process.env.DEBUG_SERVER
      logger.info "Ignoring simulated server error"
      return
    Q.delay(1).then ->
      throw new Error("Simulated server error")
