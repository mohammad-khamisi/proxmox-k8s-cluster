# clone-template

یک نمونه (VM) از یک تمپلیت موجود در Proxmox می‌سازد. **فقط تنظیمات شبکه** از روی فایل تنظیمات (`terraform.tfvars`) اعمال می‌شود و بقیه‌ی تنظیمات دقیقاً از تمپلیت کپی می‌شوند: BIOS و EFI Disk، دیسک‌ها، کنترلر SCSI، CPU و حافظه. خود تمپلیت هم دست نمی‌خورد.

این پوشه مستقل است و به بقیه‌ی ریپو ربطی ندارد.

## تنظیمات شبکه

همه در `terraform.tfvars`:

**۱. کارت شبکه** (`network_devices`): برای هر اسلات (`net0`، `net1`، ...) بریج، مدل، VLAN، MAC، فایروال و MTU. اسلاتی که نیاورید همان تنظیمات تمپلیت را نگه می‌دارد.

```hcl
network_devices = {
  net0 = { bridge = "vmbr1", model = "vmxnet3", vlan_id = 20 }
}
```

**۲. آدرس IP** (`ip_configs`، `dns_servers`، `dns_domain`): از طریق Cloud-Init. `net0` یعنی کارت اول.

```hcl
ip_configs = {
  net0 = { address = "192.168.1.80/24", gateway = "192.168.1.1" }
  # net0 = { address = "dhcp" }
}
dns_servers = ["192.168.1.1", "8.8.8.8"]
```

ریسورس `proxmox_cloned_vm` خودش Cloud-Init را مدیریت نمی‌کند، برای همین Terraform بعد از کلون این مقادیر را با یک دستور `curl` از طریق API روی VM جدید می‌نویسد (`curl` در ویندوز ۱۰ به بعد، لینوکس و مک موجود است). VM هنوز خاموش است، پس در اولین بوت اعمال می‌شوند.
برای اینکه IP واقعاً روی سیستم‌عامل بنشیند، باید داخل تمپلیت پکیج `cloud-init` نصب باشد.

## اجرا

```bash
cd clone-template
cp terraform.tfvars.example terraform.tfvars   # آدرس و توکن API و تنظیمات شبکه را بنویسید
terraform init
terraform apply
```

VM ساخته می‌شود ولی **روشن نمی‌شود**. از وب Proxmox روی `Start` بزنید و Console را ببینید.

برای تغییر شبکه بعداً: `terraform.tfvars` را عوض کنید و دوباره `terraform apply` بزنید. تغییر کارت شبکه مستقیم اعمال می‌شود. ولی Cloud-Init تغییر IP را معمولاً فقط در بوت بعدی اعمال می‌کند، پس بعد از `apply` باید VM را ری‌استارت کنید.

## حذف

```bash
terraform destroy
```

## بقیه‌ی تنظیمات

| متغیر | پیش‌فرض | توضیح |
|-------|---------|-------|
| `template_id` | `104` | تمپلیت مبدأ |
| `node_name` | `hvir111d` | نودی که VM روی آن ساخته می‌شود |
| `template_node` | خالی | نود تمپلیت، اگر با `node_name` فرق دارد |
| `datastore` | `iscsi-netapp` | محل دیسک‌های کلون؛ خالی = همان datastore تمپلیت |
| `vm_id` | `400` | ID ماشین جدید |
| `vm_name` | `clone-test` | اسم ماشین جدید |
