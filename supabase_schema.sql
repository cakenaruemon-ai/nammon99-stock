-- น้ำมนต์ 99 Stock — Supabase schema
-- Run this entire file in Supabase SQL Editor.
-- Then create employee accounts in Supabase Auth and register them in public.employees.

create extension if not exists pgcrypto;

table if not exists public.employees (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null default 'staff' check (role in ('owner','admin','staff')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

table if not exists public.cars (
  id uuid primary key default gen_random_uuid(),
  brand text not null,
  model text not null,
  trim text,
  year integer,
  plate text,
  color text,
  vin text,
  mileage integer,
  purchase_date date,
  purchase_price numeric(12,2) not null default 0,
  ttb_price numeric(12,2),
  ttb_effective_date date,
  tisco_price numeric(12,2),
  tisco_effective_date date,
  asking_price numeric(12,2),
  sold_price numeric(12,2),
  sold_date date,
  status text not null default 'พร้อมขาย' check (status in ('รอตรวจสภาพ','กำลังซ่อม','เตรียมรถ','พร้อมขาย','จองแล้ว','ขายแล้ว','ยกเลิก')),
  notes text,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

table if not exists public.car_expenses (
  id uuid primary key default gen_random_uuid(),
  car_id uuid not null references public.cars(id) on delete cascade,
  expense_type text not null,
  amount numeric(12,2) not null,
  expense_date date not null default current_date,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

table if not exists public.valuation_history (
  id uuid primary key default gen_random_uuid(),
  car_id uuid not null references public.cars(id) on delete cascade,
  institution text not null check (institution in ('TTB','Tisco')),
  price numeric(12,2) not null,
  effective_date date not null,
  note text,
  recorded_by uuid references auth.users(id),
  recorded_at timestamptz not null default now()
);

table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  entity_type text not null,
  entity_id uuid,
  action text not null,
  summary text,
  actor uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists cars_plate_idx on public.cars (plate);
create index if not exists cars_model_idx on public.cars (model);
create index if not exists cars_year_idx on public.cars (year);
create index if not exists expenses_car_idx on public.car_expenses (car_id);
create index if not exists valuation_car_idx on public.valuation_history (car_id);

create or replace function public.is_employee()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.employees e
    where e.user_id = auth.uid()
      and e.active = true
  );
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  new.updated_by = auth.uid();
  return new;
end;
$$;

drop trigger if exists cars_set_updated_at on public.cars;
create trigger cars_set_updated_at
before update on public.cars
for each row execute function public.set_updated_at();

alter table public.employees enable row level security;
alter table public.cars enable row level security;
alter table public.car_expenses enable row level security;
alter table public.valuation_history enable row level security;
alter table public.audit_log enable row level security;

drop policy if exists employees_self_read on public.employees;
create policy employees_self_read on public.employees
for select using (auth.uid() = user_id or public.is_employee());

drop policy if exists cars_employee_all on public.cars;
create policy cars_employee_all on public.cars
for all using (public.is_employee()) with check (public.is_employee());

drop policy if exists expenses_employee_all on public.car_expenses;
create policy expenses_employee_all on public.car_expenses
for all using (public.is_employee()) with check (public.is_employee());

drop policy if exists valuation_employee_all on public.valuation_history;
create policy valuation_employee_all on public.valuation_history
for all using (public.is_employee()) with check (public.is_employee());

drop policy if exists audit_employee_read on public.audit_log;
create policy audit_employee_read on public.audit_log
for select using (public.is_employee());
drop policy if exists audit_employee_insert on public.audit_log;
create policy audit_employee_insert on public.audit_log
for insert with check (public.is_employee());

-- Optional: enable Realtime so edits on one device appear on other devices.
-- If these commands say the table is already in the publication, that's harmless.
alter publication supabase_realtime add table public.cars;
alter publication supabase_realtime add table public.car_expenses;
alter publication supabase_realtime add table public.valuation_history;

-- Seed/demo data (optional). Leave commented out for a clean production database.
-- insert into public.cars (brand, model, trim, year, plate, color, purchase_date, purchase_price, ttb_price, ttb_effective_date, tisco_price, tisco_effective_date, asking_price, status)
-- values
-- ('Toyota','Yaris','1.2 Sport',2022,'กข1234','ขาว','2026-10-01',399000,420000,'2026-10-01',415000,'2026-10-01',449000,'พร้อมขาย');

-- Employee setup examples (run AFTER creating users in Auth):
-- insert into public.employees(user_id, display_name, role)
-- select id, 'เจ้าของร้าน', 'owner' from auth.users where email = 'owner@example.com'
-- on conflict (user_id) do update set display_name=excluded.display_name, role=excluded.role, active=true;
