# تثبيت مرحّل Zyrln على VPS Ubuntu عبر HTTPS واستخدامه على Android

يحتوي هذا المستودع على مثبت يضع واجهة Zyrln العامة خلف Caddy ويطبع إعدادات Apps Script النهائية. يمكن استخدام IPv4 العام للـVPS مباشرة بشهادة Let's Encrypt قصيرة العمر، أو اسم نطاق DNS عام. العناوين التي يطبعها المثبت تبدأ بـ`https://` فقط.

## المتطلبات

- VPS يعمل بـUbuntu وsystemd ومعمارية `amd64` أو `arm64`، مع root أو sudo.
- افتح **TCP 443** في جدار مزوّد VPS. إذا كان TCP 80 متاحًا، يفتحه المثبت أيضًا ليستطيع Caddy خدمة التحويل من HTTP إلى HTTPS. إذا كان 80 مشغولًا، يترك المثبت الخدمة الحالية كما هي ويستخدم تحقق TLS-ALPN عبر 443 بدلًا منه؛ في هذا الوضع لا ينشئ Caddy تحويل HTTP. إذا استخدمت نطاقًا، اجعل سجل DNS `A` يشير إلى IPv4 الخاص بالخادم. لا يلزم نطاق عند استخدام IPv4 مباشرة.[1] [2]
- لا تعرض TCP 8787 للإنترنت؛ مرحّل Zyrln يستمع إلى `127.0.0.1` فقط.
- حساب Google لنشر Apps Script Web App وهاتف Android.

تدعم Let's Encrypt شهادات IP قصيرة العمر، ومدتها 160 ساعة تقريبًا. يستخدم المثبت ملف `shortlived` ويضبط Caddy على إصدار الشهادة وتجديدها تلقائيًا. يتطلب مسار IP إصدار Caddy 2.11.7 أو أحدث.[3] [4]

## تنزيل المثبت وتشغيله

نزّل `install-zyrln-relay.sh` من المستودع الخاص وانقله إلى VPS عبر SCP. مثال:

```bash
scp ./install-zyrln-relay.sh ubuntu@YOUR_VPS_IP:~/install-zyrln-relay.sh
ssh ubuntu@YOUR_VPS_IP
chmod 700 ~/install-zyrln-relay.sh
sudo bash ~/install-zyrln-relay.sh
```

يحاول المثبت اكتشاف IPv4 العام تلقائيًا. إذا تعذّر ذلك، يطلب IPv4 أو اسم نطاق مثل `relay.example.com`. لتحديده مسبقًا استخدم `ZYRLN_HOST` أو `ZYRLN_PUBLIC_HOST`؛ و`ZYRLN_DOMAIN` مدعوم أيضًا للتوافق.

يطلب المثبت مفتاح الخروج `EXIT_RELAY_KEY` ومفتاح التطبيق `AUTH_KEY` بإدخال مخفي. اترك المطالبة فارغة لتوليد مفتاح عشوائي. في مرات التشغيل التالية، يعيد استخدام المفاتيح المحفوظة ما لم تمرر قيمًا جديدة عبر `ZYRLN_RELAY_KEY` أو `ZYRLN_APP_KEY`. لا تحفظ الأسرار في المستودع أو في سجل الأوامر.

## ما يفعله المثبت

يثبت المثبت إصدار Zyrln المستقر v2.0 من حزمة المشروع الرسمية، وينشئ خدمة systemd تحت مستخدم محدود باسم `zyrln`. كما يثبت Caddy من مستودعه الرسمي.

إذا كان العنوان IPv4، يهيئ Caddy صراحةً لإصدار شهادة Let's Encrypt بملف `shortlived`. وإذا كان اسم نطاق، يستخدم Caddy إدارة HTTPS المعتادة. عند توفر TCP 80، يحوّل Caddy HTTP إلى HTTPS. إذا كان 80 مستخدمًا، لا يوقف المثبت الخدمة المالكة له، ويضبط Caddy للعمل على 443 فقط مع TLS-ALPN لإصدار الشهادة. في الحالتين يوجّه Caddy الطلبات إلى المرحّل المحلي عبر loopback؛ لا يتصل Apps Script بالمرحّل عبر HTTP عام.[1] [3] [4]

يحفظ مفتاح الخروج في `/etc/zyrln-relay.env` بصلاحيات محدودة، ومفتاح التطبيق في `/etc/zyrln-app-key` للـroot فقط. بعد نجاح اختبار HTTPS، يطبع كتلة مثل هذه جاهزة للنسخ إلى بداية `Code.gs`:

```js
const AUTH_KEY = "المفتاح_الذي_أدخلته_أو_ولّده_المثبت";
const EXIT_RELAY_URL = "https://51.254.208.97/relay";
const EXIT_TUNNEL_URL = "https://51.254.208.97/tunnel";
const EXIT_RELAY_KEY = "مفتاح_الخروج_الذي_أدخلته_أو_ولّده_المثبت";
```

القيم أعلاه مثال فقط؛ انسخ القيم الفعلية التي يطبعها السكربت. لا ترفع المفاتيح إلى GitHub حتى لو كان المستودع خاصًا.

إذا فشل إصدار الشهادة أو اختبار HTTPS، لا يطبع السكربت إعدادًا نهائيًا بـHTTP. تحقق من عنوان الـIP أو سجل DNS ومن السماح بـTCP 443 في لوحة مزوّد VPS. لا يلزم TCP 80 لإصدار الشهادة إذا كان مستخدمًا بالفعل. راجع `journalctl -u caddy -n 100 --no-pager` وأعد تشغيل المثبت.

## جدار VPS

إذا كان UFW مفعّلًا، يضيف المثبت قاعدة TCP 443، ويضيف 80 فقط إذا كان متاحًا. لا يفعّل UFW تلقائيًا حتى لا يقطع وصول SSH. افتح TCP 443 كذلك في لوحة مزوّد VPS. لا يغيّر المثبت الخدمة التي تستخدم 80 أو يفتح المنفذ لها من UFW. إذا كان هناك سماح قديم لـ8787 من تثبيت سابق، أزل قاعدة المنفذ 8787؛ لا يحتاجه الإعداد الجديد.[5]

```bash
sudo ufw status
```

## نشر Google Apps Script

1. افتح [script.google.com](https://script.google.com) وأنشئ مشروعًا جديدًا.
2. انسخ محتوى [`Code.gs` الرسمي لإصدار v2.0](https://github.com/ajavadinezhad/zyrln/blob/v2.0/relay/deploy/apps-script/Code.gs) إلى المحرر.
3. الصق الثوابت الأربع التي طبعها المثبت في أعلى الملف بدل القيم النموذجية. تحقق أن `EXIT_RELAY_URL` و`EXIT_TUNNEL_URL` يبدأان بـ`https://`.
4. اختر **Deploy → New deployment → Web app**. استخدم **Execute as: Me** و**Who has access: Anyone**، ثم انشر ووافق على أذونات Google.
5. انسخ رابط Google المنشور المنتهي بـ`/exec`؛ هذا الرابط يوضع في Android، وليس عنوان الـVPS.

بعد أي تعديل للكود، اختر **Deploy → Manage deployments → Edit → New version → Deploy**. الحفظ وحده لا يغيّر النسخة المنشورة. قد تمنع بعض حسابات Workspace النشر العام؛ راجع مسؤول المؤسسة عندها.[6]

## استخدام تطبيق Android

نزّل APK الرسمي المنتهي بـ`-android.apk` من [إصدار Zyrln v2.0](https://github.com/ajavadinezhad/zyrln/releases/tag/v2.0). ثبّته، ثم أضف ملف اتصال داخل التطبيق. استخدم رابط Google Apps Script المنتهي بـ`/exec` في حقل URL، واستخدم قيمة `AUTH_KEY` في حقل Key. لا تضع عنوان VPS أو مفتاح الخروج في التطبيق. وافق على طلب Android لإنشاء اتصال VPN واختبر موقعًا فعليًا.

نفق Android في هذا الإصدار TCP فقط، لذلك قد لا تعمل بعض الخدمات التي تعتمد على UDP.[7]

## التحقق والصيانة

```bash
sudo systemctl status zyrln-relay caddy --no-pager
curl -i https://YOUR_VPS_IP/healthz
sudo journalctl -u zyrln-relay -n 100 --no-pager
sudo journalctl -u caddy -n 100 --no-pager
sudo ss -lntp | grep -E ':(80|443|8787)'
```

المتوقع أن يعيد فحص HTTPS `HTTP 200` و`ok`. يستمع المرحّل على `127.0.0.1:8787` فقط، بينما يتولى Caddy المنفذ 443. إذا كان 80 متاحًا، يتولى Caddy أيضًا تحويل HTTP؛ أما إذا كان مشغولًا فيظل لخدمته الحالية. على شهادة IP، يجب أن يبقى Caddy عاملًا ليجدد الشهادة القصيرة تلقائيًا.

أوامر إدارة الخدمة:

```bash
sudo systemctl restart zyrln-relay
sudo systemctl restart caddy
sudo journalctl -u caddy -n 100 --no-pager
```

## مصادر

[1]: https://caddyserver.com/docs/automatic-https "توثيق Caddy لإدارة الشهادات والتحويل إلى HTTPS"
[2]: https://caddyserver.com/docs/quick-starts/https "متطلبات Caddy لـDNS والمنافذ العامة"
[3]: https://letsencrypt.org/2026/01/15/6day-and-ip-general-availability "إتاحة شهادات IP قصيرة العمر من Let's Encrypt"
[4]: https://github.com/caddyserver/caddy/issues/7399 "تتبّع دعم Caddy لإصدار شهادات IP عبر ACME"
[5]: https://ubuntu.com/server/docs/how-to/security/firewalls "دليل Ubuntu لجدار UFW"
[6]: https://developers.google.com/apps-script/guides/web "دليل Google Apps Script Web Apps"
[7]: https://github.com/ajavadinezhad/zyrln/releases/tag/v2.0 "إصدار Zyrln v2.0"
