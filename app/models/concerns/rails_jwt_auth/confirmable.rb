module RailsJwtAuth
  module Confirmable
    def send_confirmation_instructions
      if confirmed? && !unconfirmed_email
        errors.add(:email, I18n.t('rails_jwt_auth.errors.already_confirmed'))
        return false
      end

      self.confirmation_token = SecureRandom.base58(24)
      self.confirmation_sent_at = Time.now

      mailer = Mailer.confirmation_instructions(self)
      RailsJwtAuth.deliver_later ? mailer.deliver_later : mailer.deliver
      save
    end

    def confirmed?
      confirmed_at.present?
    end

    def confirm!
      self.confirmed_at = Time.now.utc
      self.confirmation_token = nil

      if unconfirmed_email
        self.email = unconfirmed_email
        self.unconfirmed_email = nil
      end

      save
    end

    def skip_confirmation!
      self.confirmed_at = Time.now.utc
      self.confirmation_token = nil
    end

    def self.included(base)
      if base.ancestors.include? Mongoid::Document
        # include GlobalID::Identification to use deliver_later method
        # http://edgeguides.rubyonrails.org/active_job_basics.html#globalid
        base.send(:include, GlobalID::Identification) if RailsJwtAuth.deliver_later

        base.send(:field, :email,                type: String)
        base.send(:field, :unconfirmed_email,    type: String)
        base.send(:field, :confirmation_token,   type: String)
        base.send(:field, :confirmation_sent_at, type: Time)
        base.send(:field, :confirmed_at,         type: Time)
      end

      base.send(:validate, :validate_confirmation, if: :confirmed_at_changed?)

      base.send(:after_create) do
        send_confirmation_instructions unless confirmed_at || confirmation_sent_at
      end

      base.send(:before_update) do
        if email_changed? && email_was && !confirmed_at_changed?
          self.unconfirmed_email = email
          self.email = email_was
          send_confirmation_instructions
        end
      end
    end

    private

    def validate_confirmation
      return true if !confirmed_at || email_changed?

      if confirmed_at_was
        errors.add(:email, I18n.t('rails_jwt_auth.errors.already_confirmed'))
      elsif confirmation_sent_at &&
            (confirmation_sent_at < (Time.now - RailsJwtAuth.confirmation_expiration_time))
        errors.add(:confirmation_token, I18n.t('rails_jwt_auth.errors.expired'))
      end
    end
  end
end
