# تثبيت مرحّل Zyrln على VPS Ubuntu واستخدامه على Android

يثبّت هذا المستودع مرحّل Zyrln خلف Caddy ويطبع إعدادات Apps Script النهائية. عند التشغيل التفاعلي، يطلب المثبّت اختيار HTTP أو HTTPS؛ الخيار الافتراضي في المطالبة هو HTTP، ويتطلب متابعةً تأكيدًا صريحًا لأن الاتصال غير مشفّر. **HTTPS هو الخيار الموصى به** لحماية مفتاح المرحّل والبيانات أثناء النقل.

## المتطلبات

- VPS يعمل بـUbuntu وsystemd ومعمارية `amd64` أو `arm64`، مع root أو sudo.
- يطلب وضع HTTP فتح منفذ TCP عام واحد تختاره أثناء التثبيت؛ الافتراضي `8080`. يجب أن يكون المنفذ متاحًا ومسموحًا في جدار مزوّد VPS. إذا كان TCP 80 مستخدمًا، مثلًا بواسطة Xray، اختر منفذًا حرًا مثل `8080` بدلًا منه.
- يتطلب وضع HTTPS المنفذ العام TCP 443، ويتطلب TCP 80 للتحويل إلى HTTPS إن كان متاحًا. إذا كان 80 مشغولًا، يترك المثبّت خدمته كما هي ويستخدم TLS-ALPN عبر 443 من دون تحويل HTTP. يمكن استخدام IPv4 عام مباشرة أو اسم نطاق يشير سجل `A` له إلى الخادم.[1] [2]
- لا يستطيع المثبّت جعل خدمتين تستمعان مباشرةً على العنوان والمنفذ نفسيهما. مشاركة منفذ عام تتطلب إعداد وكيل أمامي لتوجيه الاتصالات للخدمات، ولا يغيّر المثبّت إعدادات الخدمة الموجودة.
- لا تعرض TCP `8787` للإنترنت؛ مرحّل Zyrln يستمع إلى `127.0.0.1` فقط.
- حساب Google لنشر Apps Script Web App وهاتف Android.

يدعم مسار HTTPS على IPv4 شهادة Let's Encrypt قصيرة العمر عبر ملف `shortlived` ويتطلب Caddy 2.11.7 أو أحدث.[3] [4]

## تنزيل المثبّت وتشغيله

```bash
scp ./install-zyrln-relay.sh ubuntu@YOUR_VPS_IP:~/install-zyrln-relay.sh
ssh ubuntu@YOUR_VPS_IP
chmod 700 ~/install-zyrln-relay.sh
sudo bash ~/install-zyrln-relay.sh
```

في التشغيل التفاعلي، اختر `1` لـHTTP أو `2` لـHTTPS. HTTP هو الاختيار الافتراضي في المطالبة، لكن المثبّت يشرح أن الاتصال غير مشفّر ويطلب كتابة `INSECURE` قبل المتابعة. بعدها أدخل المنفذ العام المطلوب؛ الافتراضي `8080`. اختر منفذًا غير مستخدم ومسموحًا في لوحة مزوّد VPS.

إذا تعذّر اكتشاف IPv4 العام تلقائيًا، يطلب المثبّت IPv4 أو اسم نطاق مثل `relay.example.com`. يمكن تحديد المضيف مسبقًا عبر `ZYRLN_HOST` أو `ZYRLN_PUBLIC_HOST`؛ و`ZYRLN_DOMAIN` مدعوم أيضًا للتوافق.

يمكن تحديد HTTP والمنفذ دون المطالبة بهما عبر متغيرات البيئة. يبقى تأكيد عدم التشفير مطلوبًا:

```bash
sudo env ZYRLN_TRANSPORT=http ZYRLN_HTTP_PORT=8080 ZYRLN_CONFIRM_INSECURE_HTTP=yes bash ~/install-zyrln-relay.sh
```

في التشغيل غير التفاعلي، يكون HTTPS هو الافتراضي ما لم تحدد `ZYRLN_TRANSPORT`. لا يسمح المثبّت بتشغيل HTTP غير التفاعلي إلا عند تمرير `ZYRLN_CONFIRM_INSECURE_HTTP=yes`.

يطلب المثبّت مفتاح الخروج `EXIT_RELAY_KEY` ومفتاح التطبيق `AUTH_KEY` بإدخال مخفي. اترك المطالبة فارغة لتوليد مفتاح عشوائي. في مرات التشغيل التالية، يعيد استخدام المفاتيح المحفوظة ما لم تمرر قيمًا جديدة عبر `ZYRLN_RELAY_KEY` أو `ZYRLN_APP_KEY`. لا تحفظ الأسرار في المستودع أو في سجل الأوامر.

## تنبيه أمني حول HTTP

HTTP لا يشفّر الاتصال. يرسل كود Apps Script مفتاح الخروج في ترويسة `X-Relay-Key`، كما تمر طلبات المرحّل وردوده عبر الاتصال؛ لذلك يمكن لمن يستطيع مراقبة المسار الشبكي قراءة البيانات أو تعديلها. اختيار منفذ مختلف لا يضيف تشفيرًا ولا يعالج هذا الخطر. استخدم HTTP فقط إذا كنت تقبل هذا الخطر، وفضّل HTTPS على شبكة عامة أو VPS متصل بالإنترنت.[8]

## ما يفعله المثبّت

يثبت المثبّت إصدار Zyrln المستقر v2.0 من حزمة المشروع الرسمية، وينشئ خدمة systemd تحت مستخدم محدود باسم `zyrln`. كما يثبت Caddy من مستودعه الرسمي، ويضبطه وكيلًا عكسيًا إلى المرحّل المحلي.

في وضع HTTP، يستمع Caddy على المضيف والمنفذ العام اللذين اخترتهما، من دون إصدار شهادة أو تشفير. في وضع HTTPS، يستخدم إدارة شهادات Caddy المعتادة للنطاق أو ملف Let's Encrypt `shortlived` لعنوان IPv4. إذا كان TCP 80 مشغولًا في وضع HTTPS، لا يوقف المثبّت خدمته؛ يستخدم TLS-ALPN عبر 443. يظل المرحّل نفسه مربوطًا إلى `127.0.0.1` في الوضعين.

يحفظ مفتاح الخروج في `/etc/zyrln-relay.env` بصلاحيات محدودة، ومفتاح التطبيق في `/etc/zyrln-app-key` للـroot فقط. بعد اختبار الصحة، يطبع إعدادات Apps Script. ستكون عناوينه مثل المثال التالي عند اختيار HTTP والمنفذ `8080`:

```js
const AUTH_KEY = "المفتاح_الذي_أدخلته_أو_ولّده_المثبت";
const EXIT_RELAY_URL = "http://51.254.208.97:8080/relay";
const EXIT_TUNNEL_URL = "http://51.254.208.97:8080/tunnel";
const EXIT_RELAY_KEY = "مفتاح_الخروج_الذي_أدخلته_أو_ولّده_المثبت";
```

أما في وضع HTTPS، فسيطبع المثبّت روابط `https://` من دون رقم منفذ عند استخدام المنفذ الافتراضي 443. انسخ القيم الفعلية التي يطبعها، ولا ترفع المفاتيح إلى GitHub حتى لو كان المستودع خاصًا.

## جدار VPS واستكشاف الأخطاء

إذا كان UFW مفعّلًا، يضيف المثبّت قاعدة للمنفذ الذي اخترته في وضع HTTP، أو قواعد HTTPS اللازمة في وضع HTTPS. لا يفعّل UFW تلقائيًا حتى لا يقطع وصول SSH. يجب أيضًا السماح بالمنفذ في لوحة مزوّد VPS. لا يحتاج المنفذ الداخلي `8787` إلى قاعدة عامة.[5]

```bash
sudo ufw status
sudo ss -lntp | grep -E ':(80|443|8080|8787)'
```

إذا اخترت منفذًا مستخدمًا، يعرض المثبّت تفاصيل المستمع ويطلب اختيار منفذ آخر؛ لا يوقف الخدمة الموجودة. إذا فشل اختبار HTTPS، تحقق من عنوان IP أو DNS ومن السماح بـTCP 443، ثم راجع `sudo journalctl -u caddy -n 100 --no-pager`. في وضع HTTP، تحقق من السماح بالمنفذ الذي اخترته ومن صحة المضيف.

## نشر Google Apps Script

1. افتح [script.google.com](https://script.google.com) وأنشئ مشروعًا جديدًا.
2. انسخ محتوى [`Code.gs` الرسمي لإصدار v2.0](https://github.com/ajavadinezhad/zyrln/blob/v2.0/relay/deploy/apps-script/Code.gs) إلى المحرر.
3. الصق الثوابت الأربع التي طبعها المثبّت في أعلى الملف بدل القيم النموذجية. لا تغيّر `http://` إلى `https://` أو العكس؛ استخدم البروتوكول الذي اختير أثناء التثبيت. تذكّر أن HTTP غير مشفّر.
4. اختر **Deploy → New deployment → Web app**. استخدم **Execute as: Me** و**Who has access: Anyone**، ثم انشر ووافق على أذونات Google.
5. انسخ رابط Google المنشور المنتهي بـ`/exec`؛ هذا الرابط يوضع في Android، وليس عنوان VPS.

بعد أي تعديل للكود، اختر **Deploy → Manage deployments → Edit → New version → Deploy**. الحفظ وحده لا يغيّر النسخة المنشورة. قد تمنع بعض حسابات Workspace النشر العام؛ راجع مسؤول المؤسسة عندها.[6]

## استخدام تطبيق Android

نزّل APK الرسمي المنتهي بـ`-android.apk` من [إصدار Zyrln v2.0](https://github.com/ajavadinezhad/zyrln/releases/tag/v2.0). ثبّته، ثم أضف ملف اتصال داخل التطبيق. استخدم رابط Google Apps Script المنتهي بـ`/exec` في حقل URL، واستخدم قيمة `AUTH_KEY` في حقل Key. لا تضع عنوان VPS أو مفتاح الخروج في التطبيق. وافق على طلب Android لإنشاء اتصال VPN واختبر موقعًا فعليًا.

نفق Android في هذا الإصدار TCP فقط، لذلك قد لا تعمل بعض الخدمات التي تعتمد على UDP.[7]

## التحقق والصيانة

عند استخدام HTTP على المنفذ `8080` مثلًا:

```bash
sudo systemctl status zyrln-relay caddy --no-pager
curl -i http://YOUR_VPS_IP:8080/healthz
sudo journalctl -u zyrln-relay -n 100 --no-pager
sudo journalctl -u caddy -n 100 --no-pager
```

في وضع HTTPS، استخدم `curl -i https://YOUR_HOST/healthz`. يجب أن يعيد فحص الصحة `HTTP 200` و`ok`. يستمع المرحّل داخليًا على `127.0.0.1:8787` افتراضيًا، ويتولى Caddy المنفذ العام المختار. يمكن تغيير المنفذ الداخلي عبر `ZYRLN_RELAY_PORT`؛ لا تعرضه مباشرة للإنترنت.

أوامر إدارة الخدمة:

```bash
sudo systemctl restart zyrln-relay
sudo systemctl restart caddy
sudo journalctl -u caddy -n 100 --no-pager
```

## المصادر

[1]: https://caddyserver.com/docs/automatic-https "توثيق Caddy لإدارة الشهادات والتحويل إلى HTTPS"
[2]: https://caddyserver.com/docs/quick-starts/https "متطلبات Caddy لـDNS والمنافذ العامة"
[3]: https://letsencrypt.org/2026/01/15/6day-and-ip-general-availability "إتاحة شهادات IP قصيرة العمر من Let's Encrypt"
[4]: https://github.com/caddyserver/caddy/issues/7399 "تتبّع دعم Caddy لإصدار شهادات IP عبر ACME"
[5]: https://ubuntu.com/server/docs/how-to/security/firewalls "دليل Ubuntu لجدار UFW"
[6]: https://developers.google.com/apps-script/guides/web "دليل Google Apps Script Web Apps"
[7]: https://github.com/ajavadinezhad/zyrln/releases/tag/v2.0 "إصدار Zyrln v2.0"
[8]: https://github.com/ajavadinezhad/zyrln/blob/main/relay/deploy/apps-script/Code.gs "كود Apps Script الرسمي وإعداد عنوان المرحّل"
