-- =====================================================================
-- น้ำมนต์ 99 Stock — Supabase schema (v3)
--
-- วิธีใช้: เปิด Supabase > SQL Editor แล้วรันไฟล์นี้ "ทั้งไฟล์"
-- • รันซ้ำได้หลายครั้ง ไม่ลบข้อมูลเดิม (ใช้ได้ทั้งโปรเจ็คใหม่และโปรเจ็คที่มีข้อมูลแล้ว)
-- • v2 เพิ่ม: ลูกค้า, การขาย, มัดจำ/จองรถ, ค้างดาวน์ + ตารางนัดจ่าย + บันทึกการติดตาม
-- • v3 เพิ่มปีจดทะเบียน (reg_year) และประเภทรถ (เก๋ง / กระบะ) ในตาราง cars และเติมให้รถเดิมอัตโนมัติจากชื่อรุ่น
-- • v2 ปรับสถานะรถเหลือ 2 แบบ: 'พร้อมขาย' และ 'ขายแล้ว'
--   (รถที่สถานะอื่นอยู่เดิม เช่น รอตรวจสภาพ/กำลังซ่อม/จองแล้ว จะถูกเปลี่ยนเป็น 'พร้อมขาย')
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1) ตารางเดิม (v1)
-- ---------------------------------------------------------------------
create table if not exists public.employees (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null default 'staff' check (role in ('owner','admin','staff')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.cars (
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
  status text not null default 'พร้อมขาย',
  notes text,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- เผื่อฐานข้อมูลเดิมยังไม่มีคอลัมน์เหล่านี้
alter table public.cars add column if not exists sold_price numeric(12,2);
alter table public.cars add column if not exists sold_date date;

create table if not exists public.car_expenses (
  id uuid primary key default gen_random_uuid(),
  car_id uuid not null references public.cars(id) on delete cascade,
  expense_type text not null,
  amount numeric(12,2) not null,
  expense_date date not null default current_date,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.valuation_history (
  id uuid primary key default gen_random_uuid(),
  car_id uuid not null references public.cars(id) on delete cascade,
  institution text not null check (institution in ('TTB','Tisco')),
  price numeric(12,2) not null,
  effective_date date not null,
  note text,
  recorded_by uuid references auth.users(id),
  recorded_at timestamptz not null default now()
);

create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  entity_type text not null,
  entity_id uuid,
  action text not null,
  summary text,
  actor uuid references auth.users(id),
  created_at timestamptz not null default now()
);

-- ปีจดทะเบียน (กรณีปีผลิตกับปีจดไม่ตรงกัน เช่น 2021-2022)
alter table public.cars add column if not exists reg_year integer;

-- ประเภทรถ: เก๋ง / กระบะ (v3)
alter table public.cars add column if not exists body_type text;
alter table public.cars drop constraint if exists cars_body_type_check;
update public.cars set body_type = case
  when concat_ws(' ', model, trim) ~* '(d-?max|ดีแม็|revo|รีโว|vigo|วีโก|hilux|ไฮลัก|ranger|เรนเจอร์|navara|นาวาร่า|triton|ไทรทัน|bt-?50|colorado|โคโลราโด|carry|แครี่|extender|กระบะ|cab|แค็บ|แคป)'
  then 'กระบะ' else 'เก๋ง' end
where body_type is null or body_type not in ('เก๋ง','กระบะ');
alter table public.cars add constraint cars_body_type_check check (body_type is null or body_type in ('เก๋ง','กระบะ'));

-- สถานะรถเหลือ 2 แบบ
alter table public.cars drop constraint if exists cars_status_check;
update public.cars set status = 'พร้อมขาย' where status is distinct from 'ขายแล้ว';
alter table public.cars alter column status set default 'พร้อมขาย';
alter table public.cars add constraint cars_status_check check (status in ('พร้อมขาย','ขายแล้ว'));

-- ---------------------------------------------------------------------
-- 2) ตารางใหม่ (v2)
-- ---------------------------------------------------------------------
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  line_id text,
  facebook text,
  source text,                       -- หน้าร้าน / Facebook / TikTok / คนรู้จักแนะนำ / อื่น ๆ
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  car_id uuid not null unique references public.cars(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  sale_price numeric(12,2) not null check (sale_price >= 0),
  sale_date date not null default current_date,
  payment_method text not null check (payment_method in ('cash','finance')),
  finance_company text,              -- TTB / Tisco / กรุงศรี / เกียรตินาคินภัทร / ชื่ออื่น
  down_payment_total numeric(12,2) not null default 0 check (down_payment_total >= 0),
  finance_amount numeric(12,2),
  installments_months integer,
  finance_commission numeric(12,2),
  customer_due numeric(12,2) not null default 0, -- ยอดที่ลูกค้าต้องจ่ายให้เต็นท์ (เงินสด = ราคาขาย, ไฟแนนซ์ = เงินดาวน์)
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_finance_company_chk check (payment_method = 'cash' or finance_company is not null)
);

create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  car_id uuid not null references public.cars(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  amount numeric(12,2) not null check (amount > 0),
  method text not null default 'cash' check (method in ('cash','transfer')),
  received_date date not null default current_date,
  pickup_date date,
  expire_date date,
  refund_policy text not null default 'no_refund' check (refund_policy in ('no_refund','full','partial')),
  customer_plan text,                -- เงินสด / ไฟแนนซ์ ... / ยังไม่แน่ใจ
  status text not null default 'active' check (status in ('active','converted','cancelled')),
  sale_id uuid references public.sales(id) on delete set null,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.down_installments (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  seq integer not null,
  amount numeric(12,2) not null check (amount > 0),
  due_date date not null,
  created_at timestamptz not null default now(),
  unique (sale_id, seq)
);

create table if not exists public.down_payments (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  paid_date date not null default current_date,
  method text not null default 'cash' check (method in ('cash','transfer','deposit')),
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.debt_followups (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  result text not null,              -- ไม่รับสาย / นัดจ่ายใหม่ / ขอผ่อนเพิ่ม / ติดต่อไม่ได้ / อื่น ๆ
  note text,
  promised_date date,
  next_followup_date date,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3) Index
-- ---------------------------------------------------------------------
create index if not exists cars_plate_idx on public.cars (plate);
create index if not exists cars_model_idx on public.cars (model);
create index if not exists cars_year_idx on public.cars (year);
create index if not exists expenses_car_idx on public.car_expenses (car_id);
create index if not exists valuation_car_idx on public.valuation_history (car_id);
create index if not exists customers_phone_idx on public.customers (phone);
create index if not exists sales_date_idx on public.sales (sale_date);
create index if not exists sales_customer_idx on public.sales (customer_id);
create index if not exists reservations_car_idx on public.reservations (car_id);
create unique index if not exists reservations_one_active_per_car on public.reservations (car_id) where status = 'active';
create index if not exists down_installments_sale_idx on public.down_installments (sale_id);
create index if not exists down_payments_sale_idx on public.down_payments (sale_id);
create index if not exists debt_followups_sale_idx on public.debt_followups (sale_id);

-- ---------------------------------------------------------------------
-- 4) Functions & triggers
-- ---------------------------------------------------------------------
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

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists cars_set_updated_at on public.cars;
create trigger cars_set_updated_at
before update on public.cars
for each row execute function public.set_updated_at();

drop trigger if exists customers_touch on public.customers;
create trigger customers_touch before update on public.customers
for each row execute function public.touch_updated_at();

drop trigger if exists sales_touch on public.sales;
create trigger sales_touch before update on public.sales
for each row execute function public.touch_updated_at();

drop trigger if exists reservations_touch on public.reservations;
create trigger reservations_touch before update on public.reservations
for each row execute function public.touch_updated_at();

-- บันทึกการขาย (ทำทุกขั้นตอนในครั้งเดียว ถ้าผิดพลาดจะไม่บันทึกครึ่ง ๆ กลาง ๆ)
-- p: { car_id, customer:{id,full_name,phone,line_id,facebook,source}, sale_price, sale_date,
--      payment_method, finance_company, down_payment_total, finance_amount, installments_months,
--      finance_commission, note, paid_today, paid_method, installments:[{amount,due_date}] }
create or replace function public.record_sale(p jsonb)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_car uuid := (p->>'car_id')::uuid;
  v_cust jsonb := coalesce(p->'customer', '{}'::jsonb);
  v_cust_id uuid := nullif(v_cust->>'id','')::uuid;
  v_method text := p->>'payment_method';
  v_price numeric := (p->>'sale_price')::numeric;
  v_down numeric := coalesce(nullif(p->>'down_payment_total','')::numeric, 0);
  v_date date := coalesce(nullif(p->>'sale_date','')::date, current_date);
  v_sale uuid;
  v_is_new boolean;
  v_res record;
  v_paid numeric := coalesce(nullif(p->>'paid_today','')::numeric, 0);
  v_item jsonb;
  v_seq int := 0;
begin
  if not public.is_employee() then
    raise exception 'ไม่มีสิทธิ์บันทึกการขาย';
  end if;
  if v_car is null or v_price is null or v_method not in ('cash','finance') then
    raise exception 'ข้อมูลการขายไม่ครบ';
  end if;

  -- ลูกค้า: แก้ไขคนเดิม หรือสร้างใหม่
  if v_cust_id is not null then
    update customers set
      full_name = coalesce(nullif(v_cust->>'full_name',''), full_name),
      phone = nullif(v_cust->>'phone',''),
      line_id = nullif(v_cust->>'line_id',''),
      facebook = nullif(v_cust->>'facebook',''),
      source = nullif(v_cust->>'source','')
    where id = v_cust_id;
  elsif coalesce(nullif(v_cust->>'full_name',''), nullif(v_cust->>'phone','')) is not null then
    insert into customers (full_name, phone, line_id, facebook, source, created_by)
    values (coalesce(nullif(v_cust->>'full_name',''), 'ลูกค้า ' || (v_cust->>'phone')),
            nullif(v_cust->>'phone',''), nullif(v_cust->>'line_id',''),
            nullif(v_cust->>'facebook',''), nullif(v_cust->>'source',''), auth.uid())
    returning id into v_cust_id;
  end if;

  select not exists (select 1 from sales where car_id = v_car) into v_is_new;

  insert into sales (car_id, customer_id, sale_price, sale_date, payment_method, finance_company,
                     down_payment_total, finance_amount, installments_months, finance_commission,
                     customer_due, note, created_by)
  values (v_car, v_cust_id, v_price, v_date, v_method,
          case when v_method = 'finance' then nullif(p->>'finance_company','') end,
          case when v_method = 'finance' then v_down else 0 end,
          case when v_method = 'finance' then nullif(p->>'finance_amount','')::numeric end,
          case when v_method = 'finance' then nullif(p->>'installments_months','')::int end,
          case when v_method = 'finance' then nullif(p->>'finance_commission','')::numeric end,
          case when v_method = 'finance' then v_down else v_price end,
          nullif(p->>'note',''), auth.uid())
  on conflict (car_id) do update set
    customer_id = excluded.customer_id,
    sale_price = excluded.sale_price,
    sale_date = excluded.sale_date,
    payment_method = excluded.payment_method,
    finance_company = excluded.finance_company,
    down_payment_total = excluded.down_payment_total,
    finance_amount = excluded.finance_amount,
    installments_months = excluded.installments_months,
    finance_commission = excluded.finance_commission,
    customer_due = excluded.customer_due,
    note = excluded.note
  returning id into v_sale;

  -- ตารางนัดจ่ายส่วนที่ค้าง (เขียนใหม่ทั้งชุด)
  delete from down_installments where sale_id = v_sale;
  for v_item in select * from jsonb_array_elements(coalesce(p->'installments','[]'::jsonb)) loop
    if coalesce(nullif(v_item->>'amount','')::numeric, 0) > 0 and nullif(v_item->>'due_date','') is not null then
      v_seq := v_seq + 1;
      insert into down_installments (sale_id, seq, amount, due_date)
      values (v_sale, v_seq, (v_item->>'amount')::numeric, (v_item->>'due_date')::date);
    end if;
  end loop;

  if v_is_new then
    -- หักมัดจำที่รับไว้แล้วให้อัตโนมัติ
    select * into v_res from reservations where car_id = v_car and status = 'active' limit 1;
    if found then
      insert into down_payments (sale_id, amount, paid_date, method, note, created_by)
      values (v_sale, v_res.amount, v_res.received_date, 'deposit', 'มัดจำจองรถ', auth.uid());
      update reservations set status = 'converted', sale_id = v_sale where id = v_res.id;
      if v_res.customer_id is not null and v_cust_id is null then
        update sales set customer_id = v_res.customer_id where id = v_sale;
      end if;
    end if;
    if v_paid > 0 then
      insert into down_payments (sale_id, amount, paid_date, method, note, created_by)
      values (v_sale, v_paid, v_date,
              case when p->>'paid_method' = 'transfer' then 'transfer' else 'cash' end,
              'ชำระวันขาย', auth.uid());
    end if;
  end if;

  update cars set status = 'ขายแล้ว', sold_price = v_price, sold_date = v_date where id = v_car;

  insert into audit_log (entity_type, entity_id, action, summary, actor)
  values ('cars', v_car, case when v_is_new then 'sale_create' else 'sale_update' end,
          case when v_is_new then 'บันทึกการขาย' else 'แก้ไขการขาย' end, auth.uid());

  return v_sale;
end;
$$;

-- ยกเลิกการขาย: ลบข้อมูลการขาย/การชำระ/การติดตาม แล้วคืนสถานะรถเป็นพร้อมขาย
-- (ถ้ามีมัดจำที่เคยหักไว้ จะคืนสถานะมัดจำเป็น "ยังจองอยู่")
create or replace function public.cancel_sale(p_sale_id uuid)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_car uuid;
begin
  if not public.is_employee() then
    raise exception 'ไม่มีสิทธิ์ยกเลิกการขาย';
  end if;
  select car_id into v_car from sales where id = p_sale_id;
  if v_car is null then
    raise exception 'ไม่พบข้อมูลการขาย';
  end if;
  update reservations set status = 'active', sale_id = null
   where sale_id = p_sale_id and status = 'converted'
     and not exists (select 1 from reservations r2 where r2.car_id = v_car and r2.status = 'active');
  delete from sales where id = p_sale_id;
  update cars set status = 'พร้อมขาย', sold_price = null, sold_date = null where id = v_car;
  insert into audit_log (entity_type, entity_id, action, summary, actor)
  values ('cars', v_car, 'sale_cancel', 'ยกเลิกการขาย', auth.uid());
end;
$$;

grant execute on function public.record_sale(jsonb) to authenticated;
grant execute on function public.cancel_sale(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5) Row Level Security: เฉพาะพนักงานที่ active เท่านั้น
-- ---------------------------------------------------------------------
alter table public.employees enable row level security;
alter table public.cars enable row level security;
alter table public.car_expenses enable row level security;
alter table public.valuation_history enable row level security;
alter table public.audit_log enable row level security;
alter table public.customers enable row level security;
alter table public.sales enable row level security;
alter table public.reservations enable row level security;
alter table public.down_installments enable row level security;
alter table public.down_payments enable row level security;
alter table public.debt_followups enable row level security;

drop policy if exists employees_self_read on public.employees;
create policy employees_self_read on public.employees
for select using (auth.uid() = user_id or public.is_employee());

do $$
declare t text;
begin
  foreach t in array array['cars','car_expenses','valuation_history','customers','sales',
                           'reservations','down_installments','down_payments','debt_followups'] loop
    execute format('drop policy if exists %I on public.%I', t || '_employee_all', t);
    execute format('create policy %I on public.%I for all using (public.is_employee()) with check (public.is_employee())',
                   t || '_employee_all', t);
  end loop;
end $$;

-- ชื่อ policy เดิมของ v1 (ลบทิ้งเพื่อไม่ให้ซ้ำ)
drop policy if exists expenses_employee_all on public.car_expenses;
drop policy if exists valuation_employee_all on public.valuation_history;

drop policy if exists audit_employee_read on public.audit_log;
create policy audit_employee_read on public.audit_log
for select using (public.is_employee());
drop policy if exists audit_employee_insert on public.audit_log;
create policy audit_employee_insert on public.audit_log
for insert with check (public.is_employee());

-- ---------------------------------------------------------------------
-- 6) Realtime: แก้ไขจากเครื่องหนึ่ง เครื่องอื่นเห็นทันที (รันซ้ำได้ ไม่ error)
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['cars','car_expenses','valuation_history','customers','sales',
                             'reservations','down_installments','down_payments','debt_followups'] loop
      if not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 7) เพิ่มพนักงาน (รันหลังสร้างบัญชีใน Authentication > Users แล้ว)
-- ---------------------------------------------------------------------
-- insert into public.employees(user_id, display_name, role)
-- select id, 'เจ้าของร้าน', 'owner' from auth.users where email = 'owner@example.com'
-- on conflict (user_id) do update set display_name=excluded.display_name, role=excluded.role, active=true;
