create schema if not exists gs_referral_tracker;

create table if not exists gs_referral_tracker.partner (
  partner_id serial primary key,
  name text not null unique,
  sector text not null,
  region text not null,
  status text not null default 'active',
  created_at timestamptz not null default now()
);

create table if not exists gs_referral_tracker.referral (
  referral_id serial primary key,
  partner_id int not null references gs_referral_tracker.partner(partner_id),
  scholar_name text not null,
  channel text not null,
  referral_date date not null,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists referral_partner_date_idx
  on gs_referral_tracker.referral(partner_id, referral_date desc);
