# ساختن تمپلیت Rocky Linux 10 با cloud-init

Terraform این پوشه IP، DNS، کاربر و کلید SSH را از طریق Cloud-Init به VM ها می‌دهد. برای اینکه این تنظیمات داخل سیستم‌عامل اعمال شوند، تمپلیت باید `cloud-init` داشته باشد. تمپلیت ۱۰۴ (منتقل‌شده از VMware) آن را ندارد. این مراحل یک بار، روی یک کپی از ۱۰۴، یک تمپلیت جدید با cloud-init می‌سازند؛ خود ۱۰۴ دست نمی‌خورد.

سیستم‌عامل: Rocky Linux 10.2

## بخش ۱: توی Proxmox

1. روی **104** راست‌کلیک کنید و **Clone** را بزنید:
   - **VM ID:** `9105`
   - **Name:** `template-rocky-10-ci`
   - **Mode:** `Full Clone`
   - **Target Storage:** `iscsi-netapp`
2. در تب **Hardware** همین VM چک کنید ردیف **CloudInit Drive (ide2)** وجود داشته باشد. اگر نبود: **Add** ← **CloudInit Drive**، و storage را `iscsi-netapp` بگذارید.
3. VM را **Start** کنید و از **Console** با `root` وارد شوید.

## بخش ۲: نصب و تنظیم cloud-init (داخل VM)

```bash
# 1) نصب پکیج‌ها
dnf -y install cloud-init cloud-utils-growpart qemu-guest-agent

# 2) cloud-init فقط از درایو Proxmox بخواند
cat > /etc/cloud/cloud.cfg.d/99-proxmox.cfg <<'CFG'
datasource_list: [ NoCloud, ConfigDrive, None ]
CFG

# 3) cloud-init همیشه موقع بوت اجرا شود (جلوی disabled-by-generator را می‌گیرد)
cat > /etc/cloud/ds-identify.cfg <<'CFG'
policy: enabled
CFG
rm -f /etc/cloud/cloud-init.disabled

# 4) فعال کردن سرویس‌ها (اسم بعضی سرویس‌ها در نسخه‌های مختلف فرق دارد، برای همین تک‌تک)
for u in cloud-init-local cloud-init-main cloud-init-network cloud-init cloud-config cloud-final qemu-guest-agent; do
  systemctl enable $u.service 2>/dev/null && echo "enabled: $u"
done

# 5) ابزارهای VMware روی Proxmox لازم نیستند
dnf -y remove open-vm-tools 2>/dev/null || true
```

## بخش ۳: تست قبل از ساختن تمپلیت

```bash
cloud-init clean --logs
reboot
```

بعد از بوت دوباره با `root` وارد شوید:

```bash
cloud-init status --long
```

باید `status: done` نشان دهد. **اگر `disabled` یا `error` بود، همین‌جا متوقف شوید** و خروجی این دستورها را بررسی کنید:

```bash
cloud-init status --long
blkid | grep -i cidata                 # باید یک خط با LABEL="cidata" نشان دهد
systemctl list-unit-files 'cloud*'     # همه باید enabled باشند
```

## بخش ۴: پاکسازی و خاموش کردن

فقط وقتی بخش ۳ `done` بود. دستور اول شبکه‌ی VM را قطع می‌کند و اشکالی ندارد: پروفایل‌های شبکه‌ی قدیمی پاک می‌شوند تا روی IP ثابتی که cloud-init می‌دهد اولویت نگیرند.

```bash
nmcli -t -f UUID connection show | xargs -r -n1 nmcli connection delete
rm -f /etc/NetworkManager/system-connections/*

cloud-init clean --logs --seed
truncate -s 0 /etc/machine-id
rm -f /etc/ssh/ssh_host_*
dnf clean all
history -c
poweroff
```

## بخش ۵: تمپلیت و Terraform

1. روی **9105** راست‌کلیک کنید و **Convert to template** را بزنید.
2. در `terraform.tfvars`:

   ```hcl
   template_id = 9105
   ```

3. در PowerShell، داخل همین پوشه:

   ```powershell
   terraform destroy
   terraform apply
   ```

## بخش ۶: چک کردن نتیجه

در Console یکی از VM های ساخته‌شده:

```bash
cloud-init status        # done
hostname                 # اسم VM، مثلاً k8s-jumpbox
ip a                     # همان IP فایل tfvars
id user1                 # کاربری که در Cloud-Init تعریف شده
```
