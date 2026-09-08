-- Active: 1787563769356@@127.0.0.1@5433@postgres@public
-- add column device_metadata to let save information about user devices during connexion

ALTER TABLE user_profiles ADD COLUMN device_metadata JSONB;