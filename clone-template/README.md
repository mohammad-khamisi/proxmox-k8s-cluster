# clone-template

یک نمونه (VM) از یک تمپلیت موجود در Proxmox می‌سازد، **بدون هیچ تغییری در تنظیمات**:
BIOS و EFI Disk، دیسک‌ها، کنترلر SCSI، کارت شبکه، CPU، حافظه و Cloud-Init همه دقیقاً از تمپلیت کپی می‌شوند.
خود تمپلیت هم دست نمی‌خورد.

از ریسورس `proxmox_cloned_vm` در provider `bpg/proxmox` استفاده می‌کند که فقط چیزهایی را که صریحاً در کد آمده مدیریت می‌کند (اینجا: فقط اسم و ID).

این پوشه مستقل است و به بقیه‌ی ریپو ربطی ندارد. برای این است که مطمئن شوید کلون تمپلیت روی Proxmox بوت می‌شود.

## اجرا

```bash
cd clone-template
cp terraform.tfvars.example terraform.tfvars   # آدرس و توکن API را بنویسید
terraform init
terraform apply
```

VM ساخته می‌شود ولی **روشن نمی‌شود** (مثل Clone دستی در Proxmox). از وب Proxmox روی `Start` بزنید و Console را ببینید.

## حذف

```bash
terraform destroy
```

## تنظیمات

| متغیر | پیش‌فرض | توضیح |
|-------|---------|-------|
| `template_id` | `104` | تمپلیت مبدأ |
| `node_name` | `hvir111d` | نودی که VM روی آن ساخته می‌شود |
| `template_node` | خالی | نود تمپلیت، اگر با `node_name` فرق دارد |
| `datastore` | `iscsi-netapp` | محل دیسک‌های کلون؛ خالی = همان datastore تمپلیت |
| `vm_id` | `400` | ID ماشین جدید |
| `vm_name` | `clone-test` | اسم ماشین جدید |
