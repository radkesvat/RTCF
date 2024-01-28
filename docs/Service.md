
# اجرای RTCF به صورت سرویس
برای اجرای برنامه به صورت سرویس مثلRTT عمل میکنیم. توجه کنید با اجرای برنامه به صورت سرویس بعد از ریستارت شدن سرور یا کرش کردن، برنامه دوباره ران میشه.

تاکید میکنم ابتدا یکبار به صورت دستی برنامه رو طبق اموزش اجرا به صورت دامین شخصی اجرا کنید تا ببینید کار میکنه یا نه. حتما از قبل اموزش اصلی رو مطالعه کنید تا با نحوه دریافت سرتیفیکیت از کلاودفلر و نحوه ذخیرش در سرور آشنا بشید.

حتما یوزر روت باشید.یکبار هم با دستور دریافت فایل و با زدن دستور cd و رفتن به مسیر روت چک کنید فایل حتما در مسیر روت باشه.فایل های cert و key هم در روت باشن.

مرحله اول به مسیر زیر وارد شید:
```sh
cd /etc/systemd/system
```

بعد باید فایل سرویس رو با nano ایجاد کنید، اسم سرویس رو یک چیز ساده بذارید تا برای فراخوانیش اذیت نشید. در اینجا مثلا از rtcf  استفاده میکنیم.
```sh
nano rtcf.service
```

بعد داخل فایل اگر **سرور ایران** هست محتویات زیر رو قرار میدید(توجه کنید با مطالعه قسمت بعد سوییچ‌ها رو تغییر بدید):

```sh
[Unit]
Description=Reverse Tunnel with CDN (aka cloudflrae) True tls support

[Service]
Type=idle
User=root
WorkingDirectory=/root
ExecStart=/root/RTCF --iran --auto:off --cert:/root/mycert.cert --pkey:/root/mykey.key --domain:* --lport:23-65535  --password:123456a --terminate:24
Restart=always

[Install]
WantedBy=multi-user.target
```

و برای **سرور خارج**:

```sh
[Unit]
Description=Reverse Tunnel with CDN (aka cloudflrae) True tls support


[Service]
Type=idle
User=root
WorkingDirectory=/root
ExecStart=/root/RTCF --kharej --auto:off --domain:* --iran-port:443 --toip:127.0.0.1 --toport:multiport --password:123456a --terminate:24
Restart=always

[Install]
WantedBy=multi-user.target
```
# تنظیم سوییچ ها

دقت کنید سوییچ ها رو بسته به نیاز خودتون تغییر بدید. بعد سوییچ --domain باید دامنتون به طور کامل با sub قرار بگیره.مثلا اگر دامنه sub.github.com در کلاودفلر روی سرورتون تنظیم شده همون رو بطور کامل در اینجا قرار میدید. برای ایران سوییچ --lport پورت هایی هست که سرور ایران به اونها گوش میده. میتونید به صورت بازه بدید مثل بالا که تمام پورت های سرور رو اشغال میکنه، در صورت لزوم بازه رو کاهش بدید تا پورت های دیگه ازاد بشن. دقت داشته باشید پورت کانفیگ هاتون و پورتی که سرور خارج میخواد بهش وصل بشه باید در این بازه باشن.

برای سرور خارج سوییچ --toport به صورت مالتیپورت تنظیم شده یعنی کاربر با هر پورتی به ایران وصل بشه با همون به خارج وصل میشه. مثلا اگه پنلتون روی پورت ۵۰۵۰ باشه و ۵۰۵۰ در بازه پورتهای سرور ایران باشه پنل رو در شرایط قطع اینترنت میتونید با ایپی ایران بالا بیارید. یا استفاده دیگه ای که من کردم پورت اس اس اچ خارج رو بردم داخل بازه ای که سرور ایران گوش میده و با ایپی ایران به خارج اس اس اچ زدم.

در سرور خارج سوییچ --iran-port پورتی که به سرور ایران باید متصل بشه رو قرار میدید. دقت کنید که اینجا دیگه هر پورتی نمیشه گذاشت چرا که سرور حالا پشت کلاودفلر قرار داره و از اونجایی که ssl تنظیم کردیم فقط پورتهای https سی دی ان کلاودفلر باید قرار بگیرند. همچنین پورت اگر ۴۴۳ قرار بدید تا خارج به ۴۴۳ ایران وصل بشه تداخلی برای سرور ایران به وجود نمیاد و باز هست و میتونید کانفیگ با پورت ۴۴۳ ایجاد کنید و همین پورت رو با ایپی ایران در کانفیگ قرار بدید. به توصیه سازنده حتما پورت ۴۴۳ قرار بدید بسیار بهتره.

Cloudflare HTTPS Ports: 443, 2053, 2083, 2087, 2096, 8443,

در RTT سازنده برای سرویس یک سوییچ ترمینیت قرار داده بود که اینجا هم قرار دادیم، اینطور هست که بعد از یک ساعت مشخصی برنامه ریستارت میشه. در بالا روی ۲۴ ساعت هست. خودتون طوری تنظیم کنید در ساعات کم بار رخ بده.

بعد از اجرای مراحل بالا و ذخیره کردن فایل ها ، ابتدا برنامه رو روی سرور ایران به اجرا در بیارید. همونطور که بالا گفتم اگر برای امتحان کردن دستور اجرا با سوییچ ها یکبار دستی چک کنید برنامه شاید درحال اجرا باشه و با دستور زیر میبندیمش:
```sh
pkill RTCF
```
بعد دستورات زیر رو به ترتیب اجرا کنید:

```sh
sudo systemctl daemon-reload
```
```sh
sudo systemctl start rtcf.service
```
```sh
sudo systemctl enable rtcf.service
```

برای چک کردن وضعیت برنامه از دستور زیر استفاده کنید:

```sh
sudo systemctl status rtcf.service
```

برای توقف برنامه از دستور زیر استفاده کنید:

```sh
sudo systemctl stop rtcf.service
```

و برای مشاهده لاگ تونل:

```sh
journalctl -u tunnel.service -e -f
```

و مقدار ثبت جزئیات برنامه رو با سوییچ --log تنظیم کنید که از ۰ تا ۴ قابل تنظیم هست. دیفالت روی یک هست و برای دیباگ کردن روی ۳ بذارید.

توجه کنید که برنامه درحال توسعه هست و برخلاف RTT توسط سازنده مدام بروزرسانی می‌شه. در صورت مشاهده باگ اون رو در ایشیوها مطرح کنید.

استاتوس برنامه در ایران و خارج شاید به صورت زیر باشه اما برنامه همچنان کار میکنه، طبق گفته سازنده اینها برای دیباگ کردن هستن:
![Screenshot 2024-01-18 170030](https://github.com/radkesvat/RTCF/assets/83896125/dceceec1-7f0a-4e8d-af00-8e99ddab6852)
![Screenshot 2024-01-18 170242](https://github.com/radkesvat/RTCF/assets/83896125/b9696869-3106-4400-a2a5-b48c133bbf25)

نمونه استاتوس دارای ارور:
![Screenshot 2024-01-18 170848](https://github.com/radkesvat/RTCF/assets/83896125/33ef3be0-3c44-4f78-84f3-50c5d0f3fbb5)
وقتی کاربر به پورتی از ایران وصل بشه که روش کانفیگ نیست مثل بالا خواهد شد.
