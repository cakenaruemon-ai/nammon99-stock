# น้ำมนต์ 99 Stock — เวอร์ชันออนไลน์หลายเครื่อง

## โครงสร้างฟรีที่แนะนำ
- Frontend: GitHub Pages หรือ Cloudflare Pages
- Database/Auth/Realtime: Supabase Free
- LINE AI: ทำเป็นขั้นถัดไปผ่าน webhook/automation หลังระบบฐานข้อมูลนิ่ง

## 1) สร้าง Supabase Project
1. สร้าง project ใหม่ใน Supabase
2. เปิด SQL Editor แล้วรัน `supabase_schema.sql` ทั้งไฟล์
3. ไปที่ Project Settings > API แล้วคัดลอก Project URL และ anon/publishable key
4. แก้ `config.js` ให้ใส่ค่าดังกล่าว
5. ที่ Authentication > Providers ตรวจสอบ Email เปิดใช้งาน
6. ปิด public signup / Disable new user signups แล้วสร้างบัญชีให้เฉพาะเจ้าของและพนักงานจาก Auth > Users
7. หลังสร้างบัญชีแล้ว เพิ่มผู้ใช้คนนั้นลง `public.employees` ตามตัวอย่างท้าย `supabase_schema.sql`

## 2) เผยแพร่เว็บไซต์
### GitHub Pages
อัปโหลด `index.html`, `config.js`, `manifest.webmanifest`, `sw.js` และไฟล์อื่นในโฟลเดอร์นี้ไปยัง repository จากนั้นเปิด Pages

หมายเหตุ: GitHub Free รองรับ Pages จาก public repository เท่านั้น ดังนั้นโค้ดหน้าเว็บอาจมองเห็นได้ แต่ข้อมูลรถอยู่ใน Supabase และถูกป้องกันด้วย RLS/Authentication

### Cloudflare Pages
อัปโหลดโฟลเดอร์นี้เป็น static site ได้เช่นกัน

## 3) ความปลอดภัย
- ใน `config.js` ใส่เฉพาะ anon/publishable key
- ห้ามใส่ service_role/secret key ในหน้าเว็บ
- ผู้ที่ไม่มีบัญชีพนักงานที่ active ใน `public.employees` จะ query/แก้ไขข้อมูลรถไม่ได้ แม้รู้ URL ของแอป
- เมื่อเอาไปใช้จริง แนะนำให้เปิด 2FA กับบัญชีอีเมล/บริการที่ใช้จัดการ Supabase และ GitHub/Cloudflare

## 4) ฟังก์ชันใน V1
- Login พนักงาน
- Search รถ
- เพิ่ม/แก้ไขรถ
- Quick input: พิมพ์สั้น / เสียง
- ตรวจจับเลขทะเบียนเพื่อแก้ไขรถคันเดิม
- ค่าใช้จ่ายแบบรายการ + รวมสะสม
- ราคากลาง TTB / Tisco แบบ manual + วันที่ข้อมูล
- ประวัติราคากลาง
- วงเงินอ้างอิง 100/95/90/85/80/70%
- สถานะรถ
- อายุสต๊อก
- Realtime sync ข้ามเครื่อง
