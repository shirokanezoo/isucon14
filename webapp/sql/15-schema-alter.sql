alter table ride_statuses add index idx_ride_id_created_at_asc(ride_id,created_at ASC);
alter table ride_statuses add index idx_ride_id_created_at_desc(ride_id,created_at DESC);
alter table chair_locations add index idx_chair_id_created_at_asc(chair_id,created_at ASC);
alter table chair_locations add index idx_chair_id_created_at_desc(chair_id,created_at DESC);
alter table rides add index idx_chair_id_updated_at_desc(chair_id,updated_at DESC);
alter table rides add index idx_user_id_created_at_desc(user_id,created_at DESC);
alter table chairs add index idx_access_token(access_token);
alter table chairs add index idx_owner_id(owner_id);
