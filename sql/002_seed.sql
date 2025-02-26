insert into gs_referral_tracker.partner (name, sector, region, status)
values
  ('Northside Scholars Network', 'Nonprofit', 'Midwest', 'active'),
  ('Bright Futures Foundation', 'Foundation', 'Northeast', 'active'),
  ('Civic Tech Alliance', 'Community', 'South', 'active'),
  ('STEM Bridge Initiative', 'Education', 'West', 'active')
on conflict (name) do nothing;

insert into gs_referral_tracker.referral (partner_id, scholar_name, channel, referral_date, notes)
select partner_id, scholar_name, channel, referral_date::date, notes
from (
  values
    ('Northside Scholars Network', 'Amina Patel', 'Warm intro', '2025-10-18', 'Referred after fall program showcase.'),
    ('Northside Scholars Network', 'Luis Ortega', 'Email', '2025-11-03', 'Needs FAFSA support.'),
    ('Bright Futures Foundation', 'Maya Chen', 'Partner portal', '2025-11-12', 'Strong STEM track record.'),
    ('Civic Tech Alliance', 'Jordan Wells', 'Event', '2025-12-01', 'Met at community hack night.'),
    ('STEM Bridge Initiative', 'Nia Johnson', 'Warm intro', '2025-12-14', 'Interested in engineering cohort.'),
    ('Bright Futures Foundation', 'Ethan Ruiz', 'Email', '2026-01-07', 'Needs essay coaching.' )
) as seed(partner_name, scholar_name, channel, referral_date, notes)
join gs_referral_tracker.partner p on p.name = seed.partner_name
on conflict do nothing;
