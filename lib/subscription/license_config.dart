/// Where the license server is and how this app identifies itself to it.
/// The license public key is added when the server learns about RentPro.
library;

const licenseServerUrl = 'https://playstore.gellsoft.com';

/// Licenses made for any other app are refused.
const licenseAudience = 'com.gellsoft.gellsoft_rentpro';

/// The Google Play subscription id (Monetize > Subscriptions). To be created
/// in the RentPro Play Console listing.
const proProductId = 'gellsoft_rentpro_pro';

/// The Web OAuth client id (Google Cloud project gellsoft-rentpro) used for
/// Google sign-in and Drive backup. A public identifier, not a secret.
const googleWebClientId =
    '425757860886-03pq2klmsjhu7cur10fk69sbf9qp5vo6.apps.googleusercontent.com';
