# Sepehr Forwarder Pro (Extended Version)

این نسخه ارتقا یافته اسکریپت سپهر برای راه‌اندازی تونل‌های GRE و SIT با تمرکز بر پایداری در شبکه ایران است.

### قابلیت‌های جدید:
- **پشتیبانی از SIT (6to4):** پایداری بسیار بیشتر نسبت به GRE در برابر فیلترینگ.
- **بهینه‌سازی خودکار MTU/MSS:** جلوگیری از دراپ شدن پکت‌های TCP.
- **Kernel Tweaks:** اعمال تنظیمات تخصصی شبکه لینوکس (BBR, Buffer size) برای کاهش پکت‌لاست.
- **مانیتورینگ زنده:** مشاهده وضعیت اتصال و ترافیک به صورت لحظه‌ای.

### نحوه نصب و اجرا HA Proxy:
```bash
bash <(curl -Ls https://raw.githubusercontent.com/Rmin-ys/gre/refs/heads/main/gre.sh)


### نحوه نصب و اجرا socat:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Rmin-ys/gre/refs/heads/main/socat.sh)
