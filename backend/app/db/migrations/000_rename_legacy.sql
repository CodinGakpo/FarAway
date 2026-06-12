-- Rename existing SQLAlchemy tables to avoid conflict with the new PostGIS schema
ALTER TABLE IF EXISTS trips RENAME TO legacy_trips;
ALTER TABLE IF EXISTS loads RENAME TO legacy_loads;
ALTER TABLE IF EXISTS matches RENAME TO legacy_matches;
ALTER TABLE IF EXISTS users RENAME TO legacy_users;
ALTER TABLE IF EXISTS ratings RENAME TO legacy_ratings;
ALTER TABLE IF EXISTS train_schedules RENAME TO legacy_train_schedules;
