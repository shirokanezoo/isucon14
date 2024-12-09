alter table chairs add column is_busy tinyint(1) not null default 0;
alter table chairs add column underway_ride_id varchar(26) not null default '';
alter table chairs add index idx_is_busy(is_busy);

alter table ride_statuses add column chair_id varchar(26) not null default '';
alter table ride_statuses add column user_id varchar(26) not null default '';
alter table ride_statuses add index idx_chair_id_and_sent_at(chair_id,chair_sent_at);
alter table ride_statuses add index idx_user_id_and_sent_at(user_id,app_sent_at);
