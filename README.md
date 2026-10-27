# proxmox-k8s-cluster

Terraform برای ساخت یک کلاستر Kubernetes با **RKE2 `v1.36.5+rke2r1`** روی Proxmox، با کلون کردن تمپلیت `104` (`template-rocky-10-50go`):

| VM | تعداد | نقش |
|----|-------|-----|
| `k8s-master-1..3` | 3 | RKE2 server (control-plane + etcd) |
| `k8s-worker-1..3` | 3 | RKE2 agent |
| `k8s-jumpbox`     | 1 | kubectl + helm + kubeconfig، دسترسی SSH به همه‌ی نودها |

```
لپ‌تاپ ──ssh──► jumpbox ──kubectl──► master-1/2/3 (:6443)
                  │
                  └──ssh──► همه‌ی نودها
```

> نصب کلاستر با Ansible روی VM های موجود (از jumpbox): پوشه‌ی [`ansible-rke2/`](ansible-rke2/).
>
> فقط می‌خواهید یک کلون ساده از تمپلیت بسازید، بدون هیچ تغییری؟ پوشه‌ی [`clone-template/`](clone-template/) را ببینید.

## چه کار می‌کند

1. هر ۷ VM را با Full Clone از تمپلیت ۱۰۴ می‌سازد و IP ثابت، کاربر و کلید SSH را با Cloud-Init خود Proxmox تنظیم می‌کند (فقط API، نیازی به SSH به نود Proxmox نیست).
2. با SSH به هر VM وصل می‌شود و `scripts/prepare-node.sh` را اجرا می‌کند: بزرگ کردن دیسک، `/etc/hosts`، خاموش کردن swap و firewalld، SELinux روی permissive، ماژول‌ها و sysctl های Kubernetes، `qemu-guest-agent`.
3. `master-1` کلاستر را راه‌اندازی می‌کند (etcd)، بعد `master-2/3` و ۳ ورکر با توکن مشترک به آن join می‌شوند (`scripts/install-rke2.sh`).
4. روی jumpbox نسخه‌ی هم‌خوان `kubectl` (`v1.36.5`) و `helm` نصب می‌شود، یک کلید SSH مخصوص jumpbox روی همه‌ی نودها قرار می‌گیرد و `kubeconfig` از `master-1` در `~/.kube/config` کپی می‌شود.

## پیش‌نیازها

- Terraform >= 1.5 روی سیستمی که به IP های VM ها دسترسی دارد.
- یک API Token در Proxmox (مثلاً `terraform@pve!provider`) با دسترسی ساخت و کلون VM و استفاده از datastore.
- داخل سیستم‌عامل تمپلیت باید پکیج `cloud-init` نصب باشد. درایو Cloud-Init را Terraform خودش روی هر کلون (ide2) اضافه می‌کند و لازم نیست در تمپلیت باشد.
- VM ها باید به اینترنت دسترسی داشته باشند (`get.rke2.io`، `dl.k8s.io`، `get.helm.sh`، مخازن dnf).
- یک کلید SSH بدون passphrase روی سیستم شما.

> **نکته‌ی مهم Rocky 10:** این نسخه به CPU از نوع `x86-64-v3` نیاز دارد؛ با نوع پیش‌فرض (`kvm64` / `x86-64-v2-AES`) بوت نمی‌شود. به همین دلیل `cpu_type = "host"` پیش‌فرض است.

## اجرا

```bash
cp terraform.tfvars.example terraform.tfvars
# IP ها، gateway، توکن API، کلید SSH و ... را ویرایش کنید
terraform init
terraform plan
terraform apply
```

بعد از اتمام (حدود ۱۰ تا ۲۰ دقیقه):

```bash
ssh rocky@<jumpbox-ip>
kubectl get nodes -o wide
k get pods -A          # alias k=kubectl
ssh k8s-master-2       # از jumpbox به هر نود
```

خروجی‌های مفید:

```bash
terraform output                                   # IP ها و دستور SSH
terraform output -raw vm_user_console_password     # رمز کنسول noVNC
terraform output -raw rke2_token                   # توکن join برای نودهای بعدی
```

## تنظیمات مهم (`terraform.tfvars`)

| متغیر | پیش‌فرض | توضیح |
|-------|---------|-------|
| `template_id` | `104` | تمپلیت مبدأ |
| `template_disk_interface` | `scsi0` | اینترفیس دیسک تمپلیت (تب Hardware) |
| `template_disk_gb` | `50` | اندازه‌ی دیسک تمپلیت؛ دیسک VM ها نمی‌تواند کوچک‌تر باشد |
| `bios` | `ovmf` | باید مثل تمپلیت باشد (UEFI) |
| `scsi_hardware` | `pvscsi` | کنترلر SCSI تمپلیت (VMware PVSCSI)؛ عوض کردنش ممکن است بوت را خراب کند |
| `network_model` | `virtio` | مدل کارت شبکه (`virtio` یا `vmxnet3`) |
| `network_bridge` | `vmbr1` | بریج شبکه |
| `vm_datastore` | `iscsi-netapp` | محل دیسک VM ها |
| `proxmox_node` / `node` | `hvir111d` | برای پخش VM ها بین `hvir211d` و `hvir213d`، فیلد `node` هر VM را تنظیم کنید (دیسک تمپلیت باید روی storage مشترک باشد) |
| `vm_user` | `rocky` | کاربری که cloud-init می‌سازد |
| `rke2_version` | `v1.36.5+rke2r1` | نسخه‌ی کلاستر |
| `rke2_install_method` | `tar` | `tar` روی هر توزیعی کار می‌کند؛ `rpm` فقط اگر مخزن RPM برای EL10 موجود باشد |
| `rke2_cni` | `canal` | `canal`، `calico`، `cilium` یا `flannel` |
| `taint_masters` | `true` | پاد های عادی روی master ها اجرا نشوند |
| `api_endpoint` | خالی | DNS یا VIP جلوی master ها (LB / kube-vip)؛ خالی = IP `master-1` |
| `provision_via_jumpbox` | `false` | `true` = Terraform فقط از طریق jumpbox به نودها SSH می‌زند |
| `agent_enabled` | `false` | فقط اگر `qemu-guest-agent` از قبل در تمپلیت نصب است `true` کنید |

## نکات

- **HA برای API:** `kubeconfig` به‌صورت پیش‌فرض به `master-1` اشاره می‌کند. برای اینکه با خاموش شدن `master-1` دسترسی قطع نشود، یک VIP (مثلاً kube-vip یا HAProxy) بسازید و در `api_endpoint` بگذارید؛ در گواهی API هم اضافه می‌شود.
- **SELinux:** نصب `tar` پالیسی `rke2-selinux` ندارد، برای همین SELinux روی permissive می‌رود (`selinux_permissive`).
- **لاگ‌ها روی هر VM:** `/var/log/rke2-setup.log` و `journalctl -u rke2-server` یا `journalctl -u rke2-agent`.
- **حذف همه چیز:** `terraform destroy`
