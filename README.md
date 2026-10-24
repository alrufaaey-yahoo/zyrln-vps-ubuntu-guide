# تثبيت مرحّل Zyrln على VPS Ubuntu مع HTTPS واستخدامه على Android

يحتوي هذا المستودع على مثبت Bash مستقل ودليل عربي لإعداد **مرحّل خروج Zyrln** على VPS Ubuntu، وتأمين الواجهة العامة عبر Caddy وشهادة TLS تلقائية، ثم ربطه بتطبيق Android عبر Google Apps Script.

> **المثبت لا يطبع عناوين Apps Script بـHTTP.** يحتاج الإعداد إلى نطاق DNS عام مثل `relay.example.com` يشير إلى VPS. يستقبل Caddy الاتصالات العامة عبر HTTPS على 443، ويحوّلها داخليًا إلى خدمة Zyrln على `127.0.0.1`. المنفذ 8787 لا يُعرض مباشرة على الإنترنت.

## الملفات

- [`install-zyrln-relay.sh`](install-zyrln-relay.sh): مثبت HTTPS ينزّل إصدار Zyrln الرسمي، يجهّز Caddy، يقيّد الخدمة إلى loopback، ويطبع الثوابت الأربع النهائية.
- [`README.md`](README.md): خطوات DNS والتثبيت والنشر والأمان واستكشاف الأعطال.

## المتطلبات قبل تشغيل المثبت

1. امتلك اسم نطاق أو نطاقًا فرعيًا عامًا، مثل `relay.example.com`.
2. أنشئ سجل DNS من النوع `A` يشير إلى IPv4 العام للـVPS. أضف سجل `AAAA` فقط إذا كان عنوان IPv6 يصل إلى الخادم ويُسمح على المنافذ المطلوبة.
3. افتح **TCP 80 وTCP 443** في لوحة مزوّد VPS. يستخدم Caddy هذين المنفذين للحصول على الشهادة وخدمة HTTPS والتحويل من HTTP إلى HTTPS. لن يعمل إصدار الشهادة إذا لم يصل النطاق إلى الخادم أو كانت المنافذ محجوبة.[1] [2]
4. استخدم Ubuntu مع systemd وصلاحية root أو sudo. يدعم المثبت `amd64` و`arm64`.
5. حساب Google لنشر Apps Script Web App، وهاتف Android لتثبيت التطبيق.

لا تستخدم عنوان IP وحده في إعدادات `EXIT_RELAY_URL` في هذا المثبت؛ يلزم hostname DNS عام يستطيع Caddy الحصول على شهادة موثوقة له. إذا كانت المنافذ 80/443 مستخدمة من موقع آخر أو كان هناك Caddyfile غير تابع لهذا المثبت، يتوقف المثبت بدل استبدال إعداد الموقع الموجود.

## تنزيل المثبت وتشغيله

نزّل `install-zyrln-relay.sh` من المستودع الخاص بعد تسجيل الدخول إلى GitHub، وانقله عبر SCP إلى الخادم. مثال:

```bash
scp ./install-zyrln-relay.sh ubuntu@YOUR_VPS_IP:~/install-zyrln-relay.sh
ssh ubuntu@YOUR_VPS_IP
```

على الخادم:

```bash
chmod 700 ~/install-zyrln-relay.sh
sudo bash ~/install-zyrln-relay.sh
```

أدخل hostname مثل `relay.example.com` عند المطالبة. يطلب المثبت كذلك مفتاح خروج `EXIT_RELAY_KEY` ومفتاح تطبيق `AUTH_KEY` بإدخال مخفي. اترك أي مطالبة سرية فارغة إذا أردت توليد مفتاح عشوائي؛ عند إعادة تشغيل المثبت، المفاتيح المحفوظة تُعاد استخدامها ما لم تمرر قيمًا جديدة.

يمكن تحديد النطاق دون مطالبة تفاعلية عبر المتغير `ZYRLN_DOMAIN`. كما يمكن تحديد مفاتيحك عبر `ZYRLN_APP_KEY` و`ZYRLN_RELAY_KEY`، والمنفذ المحلي عبر `ZYRLN_RELAY_PORT`. لا تضع الأسرار في سطر أوامر أو سجل طرفية إن أمكن؛ الإدخال المخفي أسلم.

## ما الذي يقوم به المثبت؟

المثبت مثبت على إصدار Zyrln المستقر **v2.0**. يتحقق من Ubuntu وsystemd والمعمارية، ثم ينزّل حزمة VPS الرسمية عبر HTTPS. يثبت Caddy من مستودعه الرسمي، وينشئ خدمة systemd لمرحّل Zyrln تحت مستخدم محدود باسم `zyrln`.[3]

يُضبط المرحّل ليستمع إلى `127.0.0.1:8787` فقط، وليس إلى كل واجهات الشبكة. يضيف Caddy وكيلًا عكسيًا للنطاق الذي أدخلته. يحصل Caddy تلقائيًا على شهادة TLS عامة ويجددها، ويعيد توجيه طلبات HTTP للنطاق إلى HTTPS.[1] [2]

يحفظ مفتاح الخروج في `/etc/zyrln-relay.env` بصلاحيات مقيدة. ويحفظ مفتاح التطبيق منفصلًا في `/etc/zyrln-app-key` بصلاحية root فقط؛ خدمة relay لا تحتاج إلى هذا المفتاح. بعد نجاح فحص `https://DOMAIN/healthz` يطبع القيم الأربع بهذه الصيغة:

```js
const AUTH_KEY = "المفتاح_الذي_أدخلته_أو_ولده_المثبت";
const EXIT_RELAY_URL = "https://relay.example.com/relay";
const EXIT_TUNNEL_URL = "https://relay.example.com/tunnel";
const EXIT_RELAY_KEY = "مفتاح_الخروج_الذي_أدخلته_أو_ولده_المثبت";
```

انسخ القيم الفعلية التي يطبعها السكربت إلى أعلى `Code.gs`. احفظها في مدير كلمات مرور. **لا ترفع المفاتيح إلى GitHub حتى لو كان المستودع خاصًا.**

إذا لم ينجح فحص HTTPS، يتوقف المثبت مع رسالة تحقق من DNS والمنافذ وسجل Caddy بدل أن يعرض إعدادًا نهائيًا بـHTTP. بعد إصلاح السبب، أعد تشغيله؛ يحافظ على المفاتيح المحفوظة.

## الجدار الناري

في لوحة مزوّد VPS افتح TCP 80 و443. إذا كان UFW مفعّلًا، يضيف المثبت القاعدتين. لا يفعّل UFW تلقائيًا حتى لا يقطع SSH. لا تحتاج إلى فتح 8787 للإنترنت؛ المرحّل مربوط على loopback.[4]

تحقق من UFW:

```bash
sudo ufw status
```

إذا كان مفعّلًا ولم تضاف القواعد:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

إذا سبق أن فتحت TCP 8787 في لوحة المزوّد أو UFW للمرحّل القديم، أزل تلك القاعدة. الخدمة الجديدة لا تستمع على العنوان العام في ذلك المنفذ.

## إنشاء Google Apps Script

1. افتح [script.google.com](https://script.google.com) وأنشئ مشروعًا جديدًا.
2. انسخ محتوى [`Code.gs` الرسمي المطابق للإصدار v2.0](https://github.com/ajavadinezhad/zyrln/blob/v2.0/relay/deploy/apps-script/Code.gs) إلى محرر المشروع.
3. الصق الثوابت الأربع التي طبعها المثبت في بداية `Code.gs` بدل الثوابت النموذجية. تأكد من بقاء بقية الكود كما هو. يجب أن يبدأ `EXIT_RELAY_URL` و`EXIT_TUNNEL_URL` بـ`https://`.
4. اختر **Deploy → New deployment → Web app**.
5. عيّن **Execute as: Me** و**Who has access: Anyone**، ثم اضغط **Deploy** ووافق على أذونات Google.
6. احتفظ برابط Google المنشور الذي ينتهي بـ`/exec`. هذا هو الرابط الذي يوضع في تطبيق Android؛ ليس رابط نطاق VPS.

بعد أي تعديل على `Code.gs` اذهب إلى **Deploy → Manage deployments → Edit → New version → Deploy**. حفظ الملف وحده لا يغيّر النسخة المنشورة. إذا لم يسمح حساب Workspace بخيار `Anyone`، يجب تعديل سياسة المؤسسة أو استخدام حساب مسموح.[5]

## إعداد Android

1. نزّل APK الرسمي من صفحة [إصدار v2.0](https://github.com/ajavadinezhad/zyrln/releases/tag/v2.0)، واختر الملف المنتهي بـ`-android.apk`.
2. ثبّت التطبيق واسمح مؤقتًا لمصدر التثبيت إذا طلب Android ذلك.
3. أضف ملف اتصال: في URL ضع رابط Apps Script المنشور المنتهي بـ`/exec`. في Key ضع `AUTH_KEY` من الكتلة المطبوعة.
4. اضغط **Connect** ووافق على طلب Android لإنشاء VPN.
5. اختبر فتح موقع فعلي. نجاح فحص `/healthz` لا يثبت وحده أن Apps Script وإعداد التطبيق صحيحان. نفق Android في v2.0 TCP فقط؛ قد لا تعمل مكالمات أو وظائف UDP.[6]

## التحقق والصيانة

```bash
sudo systemctl status zyrln-relay --no-pager
sudo systemctl status caddy --no-pager
curl -i https://YOUR_DOMAIN/healthz
sudo journalctl -u zyrln-relay -n 100 --no-pager
sudo journalctl -u caddy -n 100 --no-pager
sudo ss -lntp | grep -E ':(80|443|8787)'
```

النتيجة المتوقعة: HTTPS يعيد `HTTP 200` و`ok`. يفترض أن يظهر Zyrln على `127.0.0.1:8787` فقط، وCaddy على المنافذ العامة 80 و443.

لتغيير النطاق، مرّر `ZYRLN_DOMAIN` عند إعادة تشغيل المثبت بعد إعداد DNS، أو غيّر Caddyfile يدويًا بعناية. لتدوير مفتاح الخروج، حدّث `/etc/zyrln-relay.env` ثم أعد تشغيل Zyrln، وعدّل `EXIT_RELAY_KEY` في Apps Script وانشر New version. مفتاح التطبيق محفوظ منفصلًا في `/etc/zyrln-app-key`.

## استكشاف الأخطاء

**Caddy لا يحصل على شهادة:** تحقق من سجل DNS `A`/`AAAA`، ومن أن المنافذ TCP 80 و443 تصل إلى هذا الخادم من الإنترنت. راجع `journalctl -u caddy -n 100 --no-pager`. إذا كان هناك DNS proxy أو CDN، تحقق من أن طلبات ACME تصل إلى Caddy وأن وضع TLS في ذلك الوسيط لا يمنع الاتصال.

**يفشل `healthz` عبر HTTPS:** تحقق من `systemctl status zyrln-relay caddy` ومن أن `zyrln-relay` يستمع إلى `127.0.0.1:8787`. افحص أن Caddyfile يشير إلى النطاق نفسه والمنفذ المحلي الصحيح.

**Apps Script يعرض Unauthorized:** `AUTH_KEY` هو مفتاح التطبيق، و`EXIT_RELAY_KEY` هو مفتاح الخروج. تأكد من أن كل قيمة في Apps Script تطابق قيمتها في الملف/التطبيق، ثم انشر نسخة جديدة.

**يعمل الموقع عبر HTTPS لكن لا يعمل التطبيق:** تحقق من استخدام APK وCode.gs من الإصدار نفسه، ورابط Apps Script المنتهي بـ`/exec`، وأذونات VPN في Android. أوقف أي VPN آخر مؤقتًا.

## مصادر رسمية

[1]: https://caddyserver.com/docs/automatic-https "توثيق Caddy لإدارة HTTPS التلقائية والتحويلات"
[2]: https://caddyserver.com/docs/quick-starts/https "دليل Caddy الرسمي لشهادات HTTPS ومتطلبات DNS والمنافذ"
[3]: https://caddyserver.com/docs/install "تعليمات تثبيت Caddy الرسمية على Ubuntu"
[4]: https://ubuntu.com/server/docs/how-to/security/firewalls "توثيق Ubuntu لجدار UFW"
[5]: https://developers.google.com/apps-script/guides/web "توثيق Google Apps Script Web Apps"
[6]: https://github.com/ajavadinezhad/zyrln/releases/tag/v2.0 "إصدار Zyrln المستقر v2.0 وقيود نفق TCP"
