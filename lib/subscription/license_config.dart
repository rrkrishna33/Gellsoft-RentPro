/// Where the license server is and how this app identifies itself to it.
/// The license public key is added when the server learns about RentPro.
library;

/// RentPro's own copy of the license server (same code as BillPro's, with its
/// own settings, key and database), behind the same address.
const licenseServerUrl = 'https://playstore.gellsoft.com/rentpro';

/// Licenses made for any other app are refused.
const licenseAudience = 'com.gellsoft.gellsoft_rentpro';

/// The Google Play subscription id (Monetize > Subscriptions). To be created
/// in the RentPro Play Console listing.
const proProductId = 'gellsoft_pro';

/// The Web OAuth client id (Google Cloud project gellsoft-rentpro) used for
/// Google sign-in and Drive backup. A public identifier, not a secret.
const googleWebClientId =
    '425757860886-03pq2klmsjhu7cur10fk69sbf9qp5vo6.apps.googleusercontent.com';

/// Which key signed the licenses: printed by the RentPro license server when
/// its own key was made (it also serves it at /v1/public-key).
const licensePublicKeyId = 'c09d6569a9cf';

/// RentPro's license public key. It can only CHECK a license, never make one.
const licensePublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAYCT0pgiAe7ost8KnT1UqesFcJqqcysem41ht8nr3bfs=
-----END PUBLIC KEY-----
''';
