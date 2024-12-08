alter table chairs add column is_busy tinyint(1) not null default 0;
alter table chairs add index idx_is_busy(is_busy);
