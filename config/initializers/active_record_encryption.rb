key_generator = Rails.application.key_generator

ActiveRecord::Encryption.configure(
  primary_key: key_generator.generate_key("rails-builders-record-encryption-primary", 32).unpack1("H*"),
  deterministic_key: key_generator.generate_key("rails-builders-record-encryption-deterministic", 32).unpack1("H*"),
  key_derivation_salt: key_generator.generate_key("rails-builders-record-encryption-salt", 20).unpack1("H*")
)
