مقدمه

تانل معکوس با قابلیت استفاده از cdn از جمله کلود فلیر برای حل مشکل کاهش سرعت در تونل rtt 

اگر از تانل های معکوس مثل rtt استفاده کرده باشید ؛ متوجه خواهید شد که در (بیشتر نه همه ی) دیتا سنتر های ایرانی ؛ وقتی تونل رو با یه سرور خارج از دیتا سنتر هایی مثل هتزنر ؛ لینود ؛ جی کور و یا دیتیجیال انجام بدین؛
به احتمال خیلی زیاد متوجه خواهید شد که مشکل سرعت دانلود دارید روی هر کانکشن. و یا باید سرور خارج از جایی مثل والتر میخریدید که پول ترافیک گرونی دریافت میکنه یا اینکه سرور ایرانتون رو از یه سری دیتا سنتر هایی میخریدید که 
این مشکل روشون نیست ولی اون دیتا سنترا تعدادشون کمه و بیشتر دیتا سنتر های خوب و با کیفیت و ارزان قیمت رو از دست میداید.

یا اینکه باید از ایپی ۶ استفاده میکردید که این نیاز داشت سرور ایرانتون ایپی ۶ داشته باشه ولی متاسفانه تست هایی که با ایپی ۶ میزدم (دیتا سنتر آروان) ؛
در ساعات پیک ۹ تا ۱۲ شب کیفیت اش افت میکرد و این یعنی شبکه ایپی ۴ به شرط ایپی تمیز ؛ در نهایت بهتر و با کیفیت بهتر عمل میکنه و همچین روی ایپی ۴ بودن بهتر هست چون اگر روزی ایپی  ۶ بسته بشه مشکل نمیخوریم. 

این پروژه همون تونل معکوس هست که از یه سرور واسطه مثل کلود فلیر استفاده میکنه برای انتقال دیتا و این باعث میشه سیستم فیلترینگ ایران ایپی سرور خارج شما رو ایپی کلود فلیر ببینه و طبیعتا لیمیت سرعت روش قرار نخواهد داد


---
وضعیت حال حاضر پروژه ؛ در نسخه بتا هست و احتمال باگ و کرش وجود داره پس اگه تست میکنید این رو مد نظر داشته باشید که ممکنه کرش کنه و اگر کرش کرد ایشیو باز کنید و حتما لاگ هم بفرستید


برای استفاده از کلود فلیر نیاز به دامنه و سرتیفیکیت هست اما ؛ در حالت اتوماتیک برنامه خودش کارای دامنه و سرتیفیکیت رو انجام میده پس نیازی نیست خودتون این کارو بکنید


---
# نکات اولیه

من اینجا نحوه ساخت سرویس و یا nohup رو توضیح نمیدم چون فرض میکنم کسی که نسخه بتا تست میکنه این هارو بلده

برنامه در وضعیت بتا هست ؛‌ تازه منتشر شده و برطرف کردن باگ هاش نیاز به کمی زمان و تست و اپدیت داره ؛ هرچند تلاش کردم تا جای ممکن تا همینجا جلوی مشکلات گرفته بشه.

برنامه ۲ تا نسخه داره ؛ یکی single thread و یکی multi thread

نسخه single thread رو وقتی استفاده میکنید که سروری که میخواید برنامه رو در اون اجرا کنید فقط ۱ هسته داره 

نسخه multi thread رو وقتی استفاده میکنید که سروری که برنامه روش اجرا میشه بیشتر از ۱ هسته داره 

دقت کنید ؛ اگه نسخه مالتی ترد رو در یه سرور تک هسته اجرا کنید ؛ روی کیفیت اتصال و پینگ و مصرف سیپیو تاثیر بدی میزاره 

نسخه مالتی ترد به این دلیل آماده شد که بتونه کاربر زیاد رو هندل کنه ؛ اگه کاربر زیاد دارید اول مطمعن بشین که سرور ایرانتون ۲ هسته بشه بعد نسخه مالتی ترد روش نصب کنید

برای اینکه ببینید سرورتون چندتا هسته داره این دستور رو استفاده کنید

```sh
cat /proc/cpuinfo
```
و جلوی cpu cores مینویسه چند هست دارید




نکته بعد اینکه این برنامه حتما و حتما در ابتدا باید در سرور ایران اجرا بشه ؛ بعد روی سرور خارج ران بشه. 
و این یعنی فرض میکنیم برنامه در سرور ایران اگه کرش کنه ؛ باید اول برنامه رو در سرور ایران ری استارت کنید و بعد سپس برید در سرور خارج برنامه رو ری استارت کنید.


نکته بعد اینکه این روش با ایپی تیبل تداخل داره ؛ در سرور ایران برنامه رول های ایپیتیل ست میکنه و اگه شما هم به رول ها دست بزنید یا تغییر بدین از کار میفته.



# نحوه استفاده

اول باید برنامه رو دانلود کنید ؛ اگه سروری که روش نصب میکنید یک هسته داره با این دستور نصب کنید:

```sh
wget  "https://raw.githubusercontent.com/radkesvat/RTCF/master/scripts/install_st.sh" -O install_st.sh && chmod +x install_st.sh && bash install_st.sh
```

و اگه چند هسته هست این دستور:

```sh
wget  "https://raw.githubusercontent.com/radkesvat/RTCF/master/scripts/install_mt.sh" -O install_mt.sh && chmod +x install_mt.sh && bash install_mt.sh
```

فعلا چون نسخه بتا هست اینجوریه نصبش ؛‌ بعدا براش یه نصب کننده راحت مینویسم که سرویس هم بسازه ولی در حال حاضر خودتون باید اینکارا رو انجام بدید


# سرور ایران

> ./RTCF --auto:on --iran --lport:443 --password:123



--auto:on

این باعث میشه نیازی به وارد کردن سرتیفیکیت  و دامنه خودتون نداشته باشید


--lport

پورت سرور ایران ؛ میتونید یه پورت وارد کنید مثل 443 یا مالتی پورت استفاده کنید و بازه ی دلخواه رو وارد کنید مثلا از 443 تا 2000 میشه :

> --lport:443-2000


اگه میخواید مثل تونل معروف ایپی تیبل که میشه باهاش همه پورت های سرور رو تونل کرد ؛ تونل کنید باید این مقدار رو وارد کنید


> --lport:23-65535

سرور خارج هم باید درست تنظیم کنید تا مالتی پورت انجام بشه ؛ که پایین تر توضح دادم

اگه پورتی که باهاش ssh زدین به سرور (معمولا 22) رو داخل بازه قرار بدین از ssh قطع میشین و باید سرور رو از پنل فروشنده ری استارت کنید.


--password

یه رمز که باید با سرور خارج یکی باشه ؛ چیز پیچیده وارد نکنید که بعدا علت مشکل وصل نشدنتون باشه 



# سرور خارج

> ./RTCF --kharej --auto:on --iran-ip:5.4.3.2 --iran-port:443 --toip:127.0.0.1 --toport:443 --password:123


--auto:on

این باعث میشه نیازی به وارد کردن سرتیفیکیت  و دامنه خودتون نداشته باشید

--iran-ip

ایپی سرور ایران


--iran-port


پورتی که سرور ایران بهش گوش میده ؛ سرور ایران میتونه مالتی پورت هم باشه

اما نکته مهم اینه که شما در این بخش فقط میتوانید یکی از پورت های 443, 2053, 2083, 2087, 2096, 8443 را وارد کنید ؛ و در نتیجه سرور ایران هم باید به همین پورتی که اینجا وارد کردین گوش کرده باشه

اما ؛ سرور ایران میتونه مالتی پورت باشه مثلا از پورت 22 تا 2060 رو گوش کنه‌ ؛ که اگه اینطور باشه شما میتونید اینجا پورت یکی از پورت های 443 یا 2053 که داخل بازه پورتی که سرور ایران بهش گوش میده هست ؛ را وارد کنید
ترجیها ۴۴۳ وارد کنید

و اینکه این پورت تداخلی در سرور ایران ایجاد نمیکنه ؛ مثلا اینجا ۴۴۳ وارد کنید ؛ کاربر باز هم میتونه به پورت ۴۴۳ ایران وصل بشه و تبادل دیتا انجام بده

--toip


ایپی مقصد ؛ 

وقتی روی سرور خارج هستید و پنل هم روی همین سرور نصب شده باید 127.0.0.1 وارد کنید ؛ اما اگه مثلا شما میخواید ترافیک برسه به یه سرور خارج ثانویه که پنل روی اون نصبه میتونید ایپی اون سرور رو وارد کنید

اگه متوجه نشدید ؛ 127.0.0.1 وارد کنید

--toport

پورت نهایی ؛ همون پورت کانفیگی که توی پنل ساختید. ( پورت خود کانفیگ نه پورتی که وب سایت پنل روش هست!) 

اگه در سرور ایران مالتی پورت استفاده کردید ؛ اینجا باید وارد کنید "multiport" که به پورتی وصل بشه که کاربر به سرور ایران وصل شده بود ؛ اما اجباری هم نیست میتونید یه عدد وارد کنید مثلا ۴۴۳ ؛‌ اون وقت کاربر به هر پورت سرور ایران که وصل شد دیگه مهم نیست اخرش میرسه به ۴۴۳ خارج

--password

یه رمز که باید با سرور ایران یکی باشه ؛ چیز پیچیده وارد نکنید که بعدا علت مشکل وصل نشدنتون باشه 

---
# قابلیت ها جانبی


--compressor

قابلیت فشرده سازی دیتا بین سرور ایران و خارج ؛ باعث میشه تا یه درصدی (حداکثر ۱۰ درصد به نظرم) ترافیک بین المللی که مصرف میشه کمتر بشه ولی مصرف cpu بیشتر میشه

اینجا میتونید یک الگوریتم فشرده سازی انتخاب کنید. "lz4" یا "deflate"  ؛ اگه کلا قابلیت فشرده سازی نیاز ندارید این سوییچ رو اضافه نکیند

اگه از این قابلیت میخواهید استفاده کنید؛ این سوییچ رو دقیقا یکسان هم در دستور سرور ایران و هم خارج وارد کنید

پیاده سازی lz4 تکمیل نشده ولی deflate قابل استفاده هست




