/// این بسته API ندارد و import کردنش لازم نیست.
///
/// تنها دلیلِ وجودش `android/src/main/AndroidManifest.xml` است: مجوزهای
/// `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` که `geolocator_android`
/// اعلام نمی‌کند و در مانیفستِ اپ هم نمی‌توانند بمانند (CI پوشهٔ `android/`
/// را با `flutter create` از صفر می‌سازد). مانیفستِ ماژولِ پلاگین همیشه در
/// مانیفستِ نهایی merge می‌شود، پس اعلامِ مجوز اینجا پایدار است.
library dilix_permissions;
