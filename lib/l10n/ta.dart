/// Tamil text for the screens. The key is the English wording passed to
/// `tr()`. Anything missing here is shown in English.
const taStrings = <String, String>{
  // Setup
  'Welcome to {app}': '{app}-க்கு வரவேற்கிறோம்',
  'Tell us about your shop. You can change this later.':
      'உங்கள் கடையைப் பற்றிச் சொல்லுங்கள். இதை பின்னர் மாற்றலாம்.',
  'Shop details': 'கடை விவரங்கள்',
  'Shop name': 'கடையின் பெயர்',
  'Enter the shop name': 'கடையின் பெயரை உள்ளிடவும்',
  'What do you rent?': 'நீங்கள் எதை வாடகைக்கு விடுகிறீர்கள்?',
  'Phone': 'தொலைபேசி',
  'Address': 'முகவரி',
  'Save': 'சேமி',
  'Get started': 'தொடங்கு',

  // Kinds of shop
  'Costume / Dress rental': 'உடை / ஆடை வாடகை',
  'Equipment / Tools rental': 'உபகரணம் / கருவி வாடகை',
  'Party / Event decor': 'விழா / நிகழ்ச்சி அலங்காரம்',
  'Vehicle / Bike rental': 'வாகனம் / பைக் வாடகை',
  'Other': 'மற்றவை',

  // Item categories
  'Sherwani': 'ஷெர்வானி',
  'Lehenga': 'லெஹங்கா',
  'Saree': 'புடவை',
  'Gown': 'கவுன்',
  'Jewellery': 'நகைகள்',
  'Accessories': 'அணிகலன்கள்',
  'Sound system': 'ஒலி அமைப்பு',
  'Camera': 'கேமரா',
  'Lights': 'விளக்குகள்',
  'Tools': 'கருவிகள்',
  'Stage': 'மேடை',
  'Chairs and tables': 'நாற்காலிகள், மேசைகள்',
  'Flowers and decor': 'பூக்கள், அலங்காரம்',
  'Utensils': 'பாத்திரங்கள்',
  'Bike': 'பைக்',
  'Car': 'கார்',
  'Cycle': 'சைக்கிள்',
  'General': 'பொது',

  // Home and navigation
  'Home': 'முகப்பு',
  'Bookings': 'முன்பதிவுகள்',
  'Items': 'பொருட்கள்',
  'Customers': 'வாடிக்கையாளர்கள்',
  'Settings': 'அமைப்புகள்',
  'Bookings will appear here.': 'முன்பதிவுகள் இங்கே தெரியும்.',
  'Show amounts': 'தொகைகளைக் காட்டு',
  'Hide amounts': 'தொகைகளை மறை',
  'Collected this month': 'இந்த மாதம் வசூலானது',
  'Balance to collect': 'வசூலிக்க வேண்டிய மீதி',
  'Pickups today': 'இன்று எடுத்துச் செல்வது',
  'Returns today': 'இன்று திரும்புவது',
  'Overdue returns': 'தாமதமான திருப்பங்கள்',
  'Events this week': 'இந்த வார நிகழ்ச்சிகள்',

  // Items
  'Add item': 'பொருளைச் சேர்',
  'Edit item': 'பொருளை மாற்று',
  'Search items': 'பொருட்களைத் தேடு',
  'No item matches your search.': 'தேடலுக்குப் பொருந்தும் பொருள் இல்லை.',
  'Add the things you rent out, with their rate.':
      'நீங்கள் வாடகைக்கு விடும் பொருட்களை அவற்றின் வாடகையுடன் சேர்க்கவும்.',
  'a day': 'ஒரு நாளுக்கு',
  'an event': 'ஒரு நிகழ்வுக்கு',
  'Item name': 'பொருளின் பெயர்',
  'Enter the item name': 'பொருளின் பெயரை உள்ளிடவும்',
  'Category': 'வகை',
  'Size (optional)': 'அளவு (விருப்பம்)',
  'Rent (₹)': 'வாடகை (₹)',
  'Deposit (₹)': 'முன்வைப்புத் தொகை (₹)',
  'Enter the rent': 'வாடகையை உள்ளிடவும்',
  'Status': 'நிலை',
  'Notes (optional)': 'குறிப்புகள் (விருப்பம்)',
  'Per event': 'நிகழ்வுக்கு',
  'Per day': 'நாளுக்கு',
  'Available': 'கிடைக்கும்',
  'In repair': 'பழுதுபார்ப்பில்',
  'Retired': 'நீக்கப்பட்டது',
  'Remove this item?': 'இந்தப் பொருளை நீக்கவா?',
  'It will no longer be offered for new bookings. Old bookings keep it.':
      'புதிய முன்பதிவுகளுக்கு இது இனி வராது. பழைய முன்பதிவுகளில் இருக்கும்.',

  // Customers
  'Add customer': 'வாடிக்கையாளரைச் சேர்',
  'Edit customer': 'வாடிக்கையாளரை மாற்று',
  'Search by name or phone': 'பெயர் அல்லது தொலைபேசியால் தேடு',
  'No customer matches your search.':
      'தேடலுக்குப் பொருந்தும் வாடிக்கையாளர் இல்லை.',
  'Add your customers to book items for them.':
      'அவர்களுக்குப் பொருட்களை முன்பதிவு செய்ய வாடிக்கையாளர்களைச் சேர்க்கவும்.',
  'Customer name': 'வாடிக்கையாளர் பெயர்',
  'Enter the customer name': 'வாடிக்கையாளர் பெயரை உள்ளிடவும்',
  'ID shown (optional)': 'காட்டிய அடையாள அட்டை (விருப்பம்)',
  'For example: Aadhaar ending 1234': 'எடுத்துக்காட்டு: ஆதார் எண் 1234 இல் முடிவது',
  'Same phone number': 'அதே தொலைபேசி எண்',
  '{name} already has this phone number. Save anyway?':
      '{name} என்பவரிடம் ஏற்கனவே இந்த எண் உள்ளது. இருந்தாலும் சேமிக்கவா?',
  'Save anyway': 'இருந்தாலும் சேமி',
  'Remove this customer?': 'இந்த வாடிக்கையாளரை நீக்கவா?',
  'Their old bookings stay. They will leave the customer list.':
      'அவர்களின் பழைய முன்பதிவுகள் இருக்கும். வாடிக்கையாளர் பட்டியலிலிருந்து நீங்குவார்கள்.',

  // Shared
  'Cancel': 'ரத்து',
  'Remove': 'நீக்கு',
  'Error: {e}': 'பிழை: {e}',

  // Settings
  'Language': 'மொழி',
  'Theme': 'தோற்றம்',
  'Same as phone': 'தொலைபேசியைப் போலவே',
  'Light': 'வெளிச்சம்',
  'Dark': 'இருள்',
  'Version': 'பதிப்பு',

  // Pro
  'Unlimited bookings every month': 'ஒவ்வொரு மாதமும் வரம்பற்ற முன்பதிவுகள்',
  'Unlimited photos on every booking': 'ஒவ்வொரு முன்பதிவிலும் வரம்பற்ற படங்கள்',
  'Daily and custom reminder notifications':
      'தினசரி மற்றும் விருப்ப நினைவூட்டல் அறிவிப்புகள்',
};
