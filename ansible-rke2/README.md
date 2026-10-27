# ansible-rke2

نصب کلاستر Kubernetes با **RKE2 `v1.36.5+rke2r1`** روی ۳ مستر و ۳ ورکر با Ansible. اجرا از روی **jumpbox** انجام می‌شود و در پایان `kubectl` و `helm` و `kubeconfig` هم روی خود jumpbox آماده است.

فقط `ansible-core` لازم است (هیچ collection اضافه‌ای نمی‌خواهد).

| فایل | کار |
|------|-----|
| `inventory/hosts.ini` | اسم و IP نودها |
| `group_vars/all.yml` | تنظیمات: کاربر SSH، نسخه‌ی RKE2، CNI، آدرس API و ... |
| `site.yml` | ترتیب نصب |
| `tasks/prepare.yml` | آماده‌سازی سیستم‌عامل همه‌ی نودها |
| `tasks/rke2.yml` | نصب RKE2 (server یا agent) |
| `tasks/jumpbox.yml` | kubectl، helm و kubeconfig روی jumpbox |

## ترتیب نصب

1. **همه‌ی نودها:** hostname و `/etc/hosts`، بزرگ کردن پارتیشن LVM و `/var` (RKE2 همه‌ی داده‌هایش را در `/var/lib/rancher` می‌ریزد و `/var` تمپلیت فقط ~۴ گیگ است)، خاموش کردن swap و firewalld، SELinux روی permissive، ماژول‌ها و sysctl های Kubernetes.
2. **`k8s-master-1`:** کلاستر و etcd را راه می‌اندازد.
3. **`k8s-master-2` و `k8s-master-3`:** یکی‌یکی join می‌شوند (برای سلامت etcd).
4. **ورکرها:** با هم join می‌شوند.
5. **jumpbox:** `kubectl` هم‌نسخه‌ی کلاستر، `helm`، و `~/.kube/config` از `k8s-master-1`.

توکن join را خود RKE2 روی `k8s-master-1` می‌سازد و Ansible آن را مستقیم از همان‌جا می‌خواند؛ هیچ رمزی در گیت ذخیره نمی‌شود.

---

## SSH: کلید یا رمز؟

**در production همیشه کلید SSH، نه رمز.**

- رمز را می‌شود حدس زد یا brute-force کرد، و Ansible باید آن را جایی نگه دارد. کلید این مشکل‌ها را ندارد.
- cloud-init به‌طور پیش‌فرض ورود با رمز را از طریق SSH می‌بندد؛ همین خوب است. رمز `user1` فقط برای کنسول Proxmox بماند.

ساختار پیشنهادی:

```
لپ‌تاپ ──(کلید شما)──► jumpbox ──(کلید مخصوص jumpbox)──► نودها
```

- **لپ‌تاپ ← jumpbox:** با کلید خودتان (همانی که در Cloud-Init گذاشته‌اید).
- **jumpbox ← نودها:** یک کلید **جدا** که فقط روی jumpbox است. اگر روزی دسترسی را بخواهید ببندید، فقط همین کلید را از نودها حذف می‌کنید.
- برای امنیت بیشتر کلید jumpbox را با **passphrase** بسازید و با `ssh-agent` استفاده کنید (پایین‌تر).
- در شبکه (فایروال/ACL) پورت 22 نودها را فقط برای IP jumpbox باز بگذارید.

---

## مراحل اجرا

همه‌ی دستورها روی **jumpbox** و با کاربر `user1`. از لپ‌تاپ وصل شوید:

```powershell
ssh user1@<IP-jumpbox>
```

### ۱. نصب Ansible و گرفتن فایل‌ها

```bash
sudo dnf install -y ansible-core git
git clone https://github.com/mohammad-khamisi/proxmox-k8s-cluster.git
cd proxmox-k8s-cluster/ansible-rke2
```

ریپو private است؛ `git clone` نام کاربری GitHub و یک **Personal Access Token** (به‌جای رمز) می‌خواهد. یا پوشه را از لپ‌تاپ کپی کنید:

```powershell
scp -r .\ansible-rke2 user1@<IP-jumpbox>:~/
```

### ۲. ساختن کلید SSH روی jumpbox

```bash
ssh-keygen -t ed25519 -C "jumpbox-ansible" -f ~/.ssh/id_ed25519
```

(برای production یک passphrase بگذارید.)

### ۳. گذاشتن کلید jumpbox روی نودها

کلید لپ‌تاپ شما از قبل روی همه‌ی نودها هست (از Cloud-Init). از آن برای یک بار کپی کردن کلید jumpbox استفاده می‌کنیم:

**روی لپ‌تاپ (PowerShell)**، با agent forwarding به jumpbox وصل شوید:

```powershell
Get-Service ssh-agent | Set-Service -StartupType Manual
Start-Service ssh-agent
ssh-add $HOME\.ssh\id_ed25519      # کلید خودتان (اگر id_rsa است، همان را بدهید)
ssh -A user1@<IP-jumpbox>
```

**روی jumpbox:**

```bash
cd ~/proxmox-k8s-cluster/ansible-rke2     # یا ~/ansible-rke2
for ip in $(grep -oP 'ansible_host=\K\S+' inventory/hosts.ini); do
  ssh -o StrictHostKeyChecking=accept-new user1@$ip \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qF '$(cat ~/.ssh/id_ed25519.pub)' ~/.ssh/authorized_keys 2>/dev/null || echo '$(cat ~/.ssh/id_ed25519.pub)' >> ~/.ssh/authorized_keys"
done
```

بعد از این دیگر به `-A` نیازی نیست. برای VM هایی که بعداً می‌سازید، کلید عمومی jumpbox (`cat ~/.ssh/id_ed25519.pub`) را هم در تب **Cloud-Init ← SSH public key** تمپلیت اضافه کنید تا خودکار روی نودها بنشیند.

اگر کلید را با passphrase ساختید، قبل از اجرای Ansible:

```bash
eval $(ssh-agent) && ssh-add ~/.ssh/id_ed25519
```

### ۴. تنظیم inventory و متغیرها

`inventory/hosts.ini`: اسم و IP نودها را مطابق VM ها بنویسید.

`group_vars/all.yml`: حداقل این‌ها را چک کنید:

| متغیر | پیش‌فرض | توضیح |
|-------|---------|-------|
| `ansible_user` | `user1` | کاربر SSH روی نودها |
| `ansible_ssh_private_key_file` | `~/.ssh/id_ed25519` | کلید jumpbox |
| `rke2_version` | `v1.36.5+rke2r1` | نسخه‌ی کلاستر |
| `rke2_cni` | `canal` | `canal`، `calico`، `cilium` |
| `rke2_api_endpoint` | خالی | DNS یا VIP جلوی مسترها؛ خالی = IP `k8s-master-1` |
| `rke2_taint_masters` | `true` | پادهای عادی روی مسترها اجرا نشوند |
| `grow_var` | `true` | فضای آزاد دیسک به `/var` داده شود |

### ۵. تست اتصال

```bash
ansible all -m ping
ansible all -b -m command -a true
```

همه باید `SUCCESS` بدهند. اگر دومی خطای sudo (`Missing sudo password`) داد، `user1` روی نودها sudo بدون رمز ندارد؛ در آن صورت مرحله‌ی بعد را با `-K` اجرا کنید (رمز sudo را می‌پرسد).

### ۶. نصب

```bash
ansible-playbook site.yml
```

حدود ۱۰ تا ۲۰ دقیقه طول می‌کشد. در پایان لیست نودها نمایش داده می‌شود.

### ۷. استفاده

```bash
kubectl get nodes -o wide
k get pods -A          # alias k=kubectl (بعد از یک بار logout/login)
helm version
```

---

## نکته‌ها

- **اجرای دوباره امن است:** `ansible-playbook site.yml` را می‌شود دوباره اجرا کرد؛ چیزی که درست است دست نمی‌خورد. برای اضافه کردن ورکر، آن را به `[workers]` اضافه کنید و دوباره اجرا کنید.
- **HA برای API:** بدون `rke2_api_endpoint`، `kubeconfig` به `k8s-master-1` وصل است و اگر آن خاموش شود `kubectl` از jumpbox کار نمی‌کند (خود کلاستر کار می‌کند). برای production یک VIP (kube-vip یا HAProxy/keepalived) بسازید و در `rke2_api_endpoint` بگذارید.
- **SELinux:** نصب `tar` پالیسی `rke2-selinux` ندارد، برای همین SELinux روی permissive می‌رود.
- **firewalld:** خاموش می‌شود (توصیه‌ی RKE2). محدودیت دسترسی را در فایروال شبکه انجام دهید.
- **لاگ‌ها روی نودها:** `journalctl -u rke2-server -f` (مسترها) و `journalctl -u rke2-agent -f` (ورکرها).
- **روی مسترها:** با `sudo -i` مستقیم `kubectl` دارید.
