-- Demo marketplace: 5 brands, 22 published listings.
--
-- Test data, not a migration. Re-runnable, and supabase/seeds/demo_marketplace_down.sql
-- removes every row it creates.
--
-- The sellers are real auth users, so the brands have genuine separate owners and
-- the feed looks like a marketplace rather than one person talking to themselves.
-- Photos are public Wikimedia URLs rather than Storage objects: usePhotoUrl passes
-- anything starting with http straight through, so no upload is needed for demo rows.

begin;

-- Sole Exchange
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
  'soleexchange@seed.snaplist.test', '', now(), now(), now(),
  '{"provider":"seed","providers":["seed"]}', '{"full_name":"Sole Exchange"}', false, false
) on conflict (id) do nothing;
insert into public.profiles (id, display_name) values ('00000000-0000-4000-8000-000000000001', 'Sole Exchange')
  on conflict (id) do update set display_name = excluded.display_name;
insert into public.brands (id, owner_id, slug, name, bio) values (
  '10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'soleexchange', 'Sole Exchange', 'Worn-in sneakers, honestly graded.'
) on conflict (id) do update set name = excluded.name, bio = excluded.bio;

-- Attic Finds
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
  'atticfinds@seed.snaplist.test', '', now(), now(), now(),
  '{"provider":"seed","providers":["seed"]}', '{"full_name":"Attic Finds"}', false, false
) on conflict (id) do nothing;
insert into public.profiles (id, display_name) values ('00000000-0000-4000-8000-000000000002', 'Attic Finds')
  on conflict (id) do update set display_name = excluded.display_name;
insert into public.brands (id, owner_id, slug, name, bio) values (
  '10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000002', 'atticfinds', 'Attic Finds', 'Whatever was upstairs. Mostly good.'
) on conflict (id) do update set name = excluded.name, bio = excluded.bio;

-- Pixel & Pine
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
  'pixelandpine@seed.snaplist.test', '', now(), now(), now(),
  '{"provider":"seed","providers":["seed"]}', '{"full_name":"Pixel & Pine"}', false, false
) on conflict (id) do nothing;
insert into public.profiles (id, display_name) values ('00000000-0000-4000-8000-000000000003', 'Pixel & Pine')
  on conflict (id) do update set display_name = excluded.display_name;
insert into public.brands (id, owner_id, slug, name, bio) values (
  '10000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000003', 'pixelandpine', 'Pixel & Pine', 'Old electronics and newer furniture.'
) on conflict (id) do update set name = excluded.name, bio = excluded.bio;

-- Second Wind Kit
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated',
  'secondwindkit@seed.snaplist.test', '', now(), now(), now(),
  '{"provider":"seed","providers":["seed"]}', '{"full_name":"Second Wind Kit"}', false, false
) on conflict (id) do nothing;
insert into public.profiles (id, display_name) values ('00000000-0000-4000-8000-000000000004', 'Second Wind Kit')
  on conflict (id) do update set display_name = excluded.display_name;
insert into public.brands (id, owner_id, slug, name, bio) values (
  '10000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000004', 'secondwindkit', 'Second Wind Kit', 'Sports gear with one season left in it.'
) on conflict (id) do update set name = excluded.name, bio = excluded.bio;

-- The Paper Trail
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated',
  'thepapertrail@seed.snaplist.test', '', now(), now(), now(),
  '{"provider":"seed","providers":["seed"]}', '{"full_name":"The Paper Trail"}', false, false
) on conflict (id) do nothing;
insert into public.profiles (id, display_name) values ('00000000-0000-4000-8000-000000000005', 'The Paper Trail')
  on conflict (id) do update set display_name = excluded.display_name;
insert into public.brands (id, owner_id, slug, name, bio) values (
  '10000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000005', 'thepapertrail', 'The Paper Trail', 'Books, records, and the odd camera.'
) on conflict (id) do update set name = excluded.name, bio = excluded.bio;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'Nike Air Max 90, white / laser pink, UK 8',
  'Listed by a demo seller. Nike Air Max 90, white / laser pink, UK 8.',
  6500, 'USD', 'good', 1, null, 'shoes', 'Nike',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/6/6e/Air_Max_97.jpg/960px-Air_Max_97.jpg'], array['snaplist'], now() - interval '1 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000003', 'adidas Superstar, white / black, UK 9',
  'Listed by a demo seller. adidas Superstar, white / black, UK 9.',
  4000, 'USD', 'good', 1, null, 'shoes', 'adidas',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/5/59/Adidas_Superstar_shoes_pair.jpg/960px-Adidas_Superstar_shoes_pair.jpg'], array['snaplist'], now() - interval '2 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000004', 'Converse Chuck Taylor All Star low, black, UK 7',
  'Listed by a demo seller. Converse Chuck Taylor All Star low, black, UK 7.',
  2200, 'USD', 'fair', 1, null, 'shoes', 'Converse',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a2/Red_and_blue_Chuck_Taylor_All-Stars_sneakers%2C_2010.jpg/960px-Red_and_blue_Chuck_Taylor_All-Stars_sneakers%2C_2010.jpg'], array['snaplist'], now() - interval '3 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000005', 'Dr. Martens 1460, cherry red, UK 8',
  'Listed by a demo seller. Dr. Martens 1460, cherry red, UK 8.',
  7500, 'USD', 'good', 1, null, 'shoes', 'Dr. Martens',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/b/bf/Dr_martens_steel_toe_boots.jpg/960px-Dr_martens_steel_toe_boots.jpg'], array['snaplist'], now() - interval '4 hours', true
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Nintendo Switch, neon Joy-Con, console only',
  'Listed by a demo seller. Nintendo Switch, neon Joy-Con, console only.',
  15000, 'USD', 'good', 1, null, 'toys', 'Nintendo',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/7/76/Nintendo-Switch-Console-Docked-wJoyConRB.jpg/960px-Nintendo-Switch-Console-Docked-wJoyConRB.jpg'], array['snaplist'], now() - interval '5 hours', true
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000006', '00000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'Game Boy Pocket, silver, tested and working',
  'Listed by a demo seller. Game Boy Pocket, silver, tested and working.',
  8000, 'USD', 'fair', 1, null, 'toys', 'Nintendo',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/8/8f/Game-Boy-Original.jpg/960px-Game-Boy-Original.jpg'], array['snaplist'], now() - interval '6 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000007', '00000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000003', 'Rubik''s Cube, original 3x3, boxed',
  'Listed by a demo seller. Rubik''s Cube, original 3x3, boxed.',
  900, 'USD', 'like_new', 1, null, 'toys', 'Rubik''s',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/9/9a/Rubik%27s_Cube_variants.jpg/960px-Rubik%27s_Cube_variants.jpg'], array['snaplist'], now() - interval '7 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000008', '00000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000004', 'Weighted wooden chess set, full pieces',
  'Listed by a demo seller. Weighted wooden chess set, full pieces.',
  3500, 'USD', 'good', 1, null, 'toys', null,
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/4/40/Chess_game_Staunton_No._6_perfil_view_8.jpg/960px-Chess_game_Staunton_No._6_perfil_view_8.jpg'], array['snaplist'], now() - interval '8 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000009', '00000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000005', 'Canon AE-1 35mm SLR, body only',
  'Listed by a demo seller. Canon AE-1 35mm SLR, body only.',
  12000, 'USD', 'fair', 1, null, 'electronics', 'Canon',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/3/3b/Vintage_Beacon_II_Film_Camera_By_Whitehouse_Products_With_Optional_Flash_Unit_%2822274785336%29.jpg/960px-Vintage_Beacon_II_Film_Camera_By_Whitehouse_Products_With_Optional_Flash_Unit_%2822274785336%29.jpg'], array['snaplist'], now() - interval '9 hours', true
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000010', '00000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Technics SL-1200 turntable, serviced',
  'Listed by a demo seller. Technics SL-1200 turntable, serviced.',
  42000, 'USD', 'good', 1, null, 'electronics', 'Technics',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c5/Edison_and_phonograph_edit2.jpg/960px-Edison_and_phonograph_edit2.jpg'], array['snaplist'], now() - interval '10 hours', true
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000011', '00000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'Anglepoise 1227 desk lamp, brass',
  'Listed by a demo seller. Anglepoise 1227 desk lamp, brass.',
  9500, 'USD', 'good', 1, null, 'home', 'Anglepoise',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/1/12/Type_1228_desk_lamp%2C_designed_by_Kenneth_Grange%2C_made_by_Anglepoise%2C_2004_-_Design_Museum%2C_Kensington_-_London_-_DSC01568.jpg/960px-Type_1228_desk_lamp%2C_designed_by_Kenneth_Grange%2C_made_by_Anglepoise%2C_2004_-_Design_Museum%2C_Kensington_-_London_-_DSC01568.jpg'], array['snaplist'], now() - interval '11 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000012', '00000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000003', 'Cast iron skillet, 10 inch, seasoned',
  'Listed by a demo seller. Cast iron skillet, 10 inch, seasoned.',
  2800, 'USD', 'good', 1, null, 'home', null,
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d3/Cast_iron_dutch_baby_on_oven_mitts.jpg/960px-Cast_iron_dutch_baby_on_oven_mitts.jpg'], array['snaplist'], now() - interval '12 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000013', '00000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000004', 'Acoustic guitar, dreadnought, with soft case',
  'Listed by a demo seller. Acoustic guitar, dreadnought, with soft case.',
  11000, 'USD', 'good', 1, null, 'other', null,
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/e/e0/Man_playing_an_acoustic_brazilian_guitar_%28Viol%C3%A3o%29_on_Marco_Zero_Square%2C_Refice%2C_Pernambuco%2C_Brazil.jpg/960px-Man_playing_an_acoustic_brazilian_guitar_%28Viol%C3%A3o%29_on_Marco_Zero_Square%2C_Refice%2C_Pernambuco%2C_Brazil.jpg'], array['snaplist'], now() - interval '13 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000014', '00000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000005', 'Vinyl LP, original pressing, sleeve VG+',
  'Listed by a demo seller. Vinyl LP, original pressing, sleeve VG+.',
  1800, 'USD', 'good', 1, null, 'books', null,
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b6/12in-Vinyl-LP-Record-Angle.jpg/960px-12in-Vinyl-LP-Record-Angle.jpg'], array['snaplist'], now() - interval '14 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000015', '00000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Penguin clothbound classics, set of four',
  'Listed by a demo seller. Penguin clothbound classics, set of four.',
  4500, 'USD', 'like_new', 1, null, 'books', 'Penguin',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/1/10/A_Stack_of_Books.png/960px-A_Stack_of_Books.png'], array['snaplist'], now() - interval '15 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000016', '00000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'Polaroid 600 instant camera, working',
  'Listed by a demo seller. Polaroid 600 instant camera, working.',
  5500, 'USD', 'fair', 1, null, 'electronics', 'Polaroid',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/8/8e/2023_Aparat_Polaroid_Land_Camera_Supercolor_1000_%285%29.jpg/960px-2023_Aparat_Polaroid_Land_Camera_Supercolor_1000_%285%29.jpg'], array['snaplist'], now() - interval '16 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000017', '00000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000003', 'Tennis racket, grip re-wrapped, no cover',
  'Listed by a demo seller. Tennis racket, grip re-wrapped, no cover.',
  3200, 'USD', 'fair', 1, null, 'sports', null,
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/a/ab/Rich%C3%A8l_Hogenkamp_-_Masters_de_Madrid_2015_-_11.jpg/960px-Rich%C3%A8l_Hogenkamp_-_Masters_de_Madrid_2015_-_11.jpg'], array['snaplist'], now() - interval '17 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000018', '00000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000004', 'Road cycling helmet, size M, unworn',
  'Listed by a demo seller. Road cycling helmet, size M, unworn.',
  4000, 'USD', 'like_new', 1, null, 'sports', null,
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/8/8d/ABUS%2C_Eurobike_2024%2C_Frankfurt_am_Main_%28LRM_20240707_144137-RR%29.jpg/960px-ABUS%2C_Eurobike_2024%2C_Frankfurt_am_Main_%28LRM_20240707_144137-RR%29.jpg'], array['snaplist'], now() - interval '18 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000019', '00000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000005', 'Cast iron dumbbells, 2 x 10kg',
  'Listed by a demo seller. Cast iron dumbbells, 2 x 10kg.',
  3000, 'USD', 'good', 1, null, 'sports', null,
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/7/7d/M27-Dumbbell_Nebula-29-07-2026.jpg/960px-M27-Dumbbell_Nebula-29-07-2026.jpg'], array['snaplist'], now() - interval '19 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000020', '00000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Denim trucker jacket, mid wash, size L',
  'Listed by a demo seller. Denim trucker jacket, mid wash, size L.',
  5500, 'USD', 'good', 1, null, 'clothing', 'Levi''s',
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/9/90/Denim_jacket_from_Dolce_%26_Gabbana_with_human_skull_on_back_made_from_Swarovski_glass_crystals.jpg/960px-Denim_jacket_from_Dolce_%26_Gabbana_with_human_skull_on_back_made_from_Swarovski_glass_crystals.jpg'], array['snaplist'], now() - interval '20 hours', true
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000021', '00000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'Wool overcoat, charcoal, size 40R',
  'Listed by a demo seller. Wool overcoat, charcoal, size 40R.',
  8500, 'USD', 'good', 1, null, 'clothing', null,
  array['https://upload.wikimedia.org/wikipedia/commons/f/f0/1920_woman%27s_coat_in_boteh_patterned_wool_with_fur_collar.jpg'], array['snaplist'], now() - interval '21 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

insert into public.listings (
  id, user_id, brand_id, title, description, price_cents, currency, condition, quantity,
  category, category_slug, brand, photos, channels, published_at, is_featured
) values (
  '20000000-0000-4000-8000-000000000022', '00000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000003', 'Leather shoulder bag, tan, light patina',
  'Listed by a demo seller. Leather shoulder bag, tan, light patina.',
  6500, 'USD', 'good', 1, null, 'clothing', null,
  array['https://thumb.wikimedia.org/wikipedia/commons/thumb/1/13/Kelly_Bag.jpg/960px-Kelly_Bag.jpg'], array['snaplist'], now() - interval '22 hours', false
) on conflict (id) do update set
  title = excluded.title, price_cents = excluded.price_cents,
  category_slug = excluded.category_slug, photos = excluded.photos,
  is_featured = excluded.is_featured, published_at = excluded.published_at;

commit;
