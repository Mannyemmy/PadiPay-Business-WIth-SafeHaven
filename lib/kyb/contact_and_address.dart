import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padi_pay_business/feedback.dart';
import 'package:padi_pay_business/ui/permission_explanation_sheet.dart';
import 'package:padi_pay_business/utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactAndAddress extends StatefulWidget {
  const ContactAndAddress({super.key});

  @override
  State<ContactAndAddress> createState() => _ContactAndAddressState();
}

class _ContactAndAddressState extends State<ContactAndAddress> {
  final String selectedCountry = 'Nigeria';
  final List<String> states = [
    'Abia',
    'Adamawa',
    'Akwa Ibom',
    'Anambra',
    'Bauchi',
    'Bayelsa',
    'Benue',
    'Borno',
    'Cross River',
    'Delta',
    'Ebonyi',
    'Edo',
    'Ekiti',
    'Enugu',
    'Gombe',
    'Imo',
    'Jigawa',
    'Kaduna',
    'Kano',
    'Katsina',
    'Kebbi',
    'Kogi',
    'Kwara',
    'Lagos',
    'Nasarawa',
    'Niger',
    'Ogun',
    'Ondo',
    'Osun',
    'Oyo',
    'Plateau',
    'Rivers',
    'Sokoto',
    'Taraba',
    'Yobe',
    'Zamfara',
    'Federal Capital Territory',
  ];
  String? selectedState;
  List<String> cities = [];
  String? selectedCity;
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _ninController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();

  final Map<String, List<String>> stateToCities = {
    'Abia': [
      'Aba North',
      'Aba South',
      'Arochukwu',
      'Bende',
      'Ikwuano',
      'Isiala-Ngwa North',
      'Isiala-Ngwa South',
      'Isuikwato',
      'Obi Nwa',
      'Ohafia',
      'Osisioma',
      'Ngwa',
      'Ugwunagbo',
      'Ukwa East',
      'Ukwa West',
      'Umuahia North',
      'Umuahia South',
      'Umu-Neochi',
    ],
    'Adamawa': [
      'Demsa',
      'Fufore',
      'Ganaye',
      'Gireri',
      'Gombi',
      'Guyuk',
      'Hong',
      'Jada',
      'Lamurde',
      'Madagali',
      'Maiha',
      'Mayo-Belwa',
      'Michika',
      'Mubi North',
      'Mubi South',
      'Numan',
      'Shelleng',
      'Song',
      'Toungo',
      'Yola North',
      'Yola South',
    ],
    'Akwa Ibom': [
      'Abak',
      'Eastern Obolo',
      'Eket',
      'Esit Eket',
      'Essien Udim',
      'Etim Ekpo',
      'Etinan',
      'Ibeno',
      'Ibesikpo Asutan',
      'Ibiono Ibom',
      'Ika',
      'Ikono',
      'Ikot Abasi',
      'Ikot Ekpene',
      'Ini',
      'Itu',
      'Mbo',
      'Mkpat Enin',
      'Nsit Atai',
      'Nsit Ibom',
      'Nsit Ubium',
      'Obot Akara',
      'Okobo',
      'Onna',
      'Oron',
      'Oruk Anam',
      'Udung Uko',
      'Ukanafun',
      'Uruan',
      'Urue-Offong/Oruko',
      'Uyo',
    ],
    'Anambra': [
      'Aguata',
      'Anambra East',
      'Anambra West',
      'Anaocha',
      'Awka North',
      'Awka South',
      'Ayamelum',
      'Dunukofia',
      'Ekwusigo',
      'Idemili North',
      'Idemili South',
      'Ihiala',
      'Njikoka',
      'Nnewi North',
      'Nnewi South',
      'Ogbaru',
      'Onitsha North',
      'Onitsha South',
      'Orumba North',
      'Orumba South',
      'Oyi',
    ],
    'Bauchi': [
      'Alkaleri',
      'Bauchi',
      'Bogoro',
      'Damban',
      'Darazo',
      'Dass',
      'Ganjuwa',
      'Giade',
      'Itas/Gadau',
      'Jama\'are',
      'Katagum',
      'Kirfi',
      'Misau',
      'Ningi',
      'Shira',
      'Tafawa-Balewa',
      'Toro',
      'Warji',
      'Zaki',
    ],
    'Bayelsa': [
      'Brass',
      'Ekeremor',
      'Kolokuma/Opokuma',
      'Nembe',
      'Ogbia',
      'Sagbama',
      'Southern Jaw',
      'Yenegoa',
    ],
    'Benue': [
      'Ado',
      'Agatu',
      'Apa',
      'Buruku',
      'Gboko',
      'Guma',
      'Gwer East',
      'Gwer West',
      'Katsina-Ala',
      'Konshisha',
      'Kwande',
      'Logo',
      'Makurdi',
      'Obi',
      'Ogbadibo',
      'Oju',
      'Okpokwu',
      'Ohimini',
      'Oturkpo',
      'Tarka',
      'Ukum',
      'Ushongo',
      'Vandeikya',
    ],
    'Borno': [
      'Abadam',
      'Askira/Uba',
      'Bama',
      'Bayo',
      'Biu',
      'Chibok',
      'Damboa',
      'Dikwa',
      'Gubio',
      'Guzamala',
      'Gwoza',
      'Hawul',
      'Jere',
      'Kaga',
      'Kala/Balge',
      'Konduga',
      'Kukawa',
      'Kwaya Kusar',
      'Mafa',
      'Magumeri',
      'Maiduguri',
      'Marte',
      'Mobbar',
      'Monguno',
      'Ngala',
      'Nganzai',
      'Shani',
    ],
    'Cross River': [
      'Akpabuyo',
      'Odukpani',
      'Akamkpa',
      'Biase',
      'Abi',
      'Ikom',
      'Yarkur',
      'Odubra',
      'Boki',
      'Ogoja',
      'Yala',
      'Obanliku',
      'Obudu',
      'Calabar South',
      'Etung',
      'Bekwara',
      'Bakassi',
      'Calabar Municipality',
    ],
    'Delta': [
      'Oshimili',
      'Aniocha',
      'Aniocha South',
      'Ika South',
      'Ika North-East',
      'Ndokwa West',
      'Ndokwa East',
      'Isoko South',
      'Isoko North',
      'Bomadi',
      'Burutu',
      'Ughelli South',
      'Ughelli North',
      'Ethiope West',
      'Ethiope East',
      'Sapele',
      'Okpe',
      'Warri North',
      'Warri South',
      'Uvwie',
      'Udu',
      'Warri Central',
      'Ukwani',
      'Oshimili North',
      'Patani',
    ],
    'Ebonyi': [
      'Edda',
      'Afikpo',
      'Onicha',
      'Ohaozara',
      'Abakaliki',
      'Ishielu',
      'lkwo',
      'Ezza',
      'Ezza South',
      'Ohaukwu',
      'Ebonyi',
      'Ivo',
    ],
    'Edo': [
      'Esan North-East',
      'Esan Central',
      'Esan West',
      'Egor',
      'Ikpoba',
      'Central',
      'Etsako Central',
      'Igueben',
      'Oredo',
      'Ovia SouthWest',
      'Ovia South-East',
      'Orhionwon',
      'Uhunmwonde',
      'Etsako East',
      'Esan South-East',
    ],
    'Ekiti': [
      'Ado',
      'Ekiti-East',
      'Ekiti-West',
      'Emure/Ise/Orun',
      'Ekiti South-West',
      'Ikere',
      'Irepodun',
      'Ijero',
      'Ido/Osi',
      'Oye',
      'Ikole',
      'Moba',
      'Gbonyin',
      'Efon',
      'Ise/Orun',
      'Ilejemeje',
    ],
    'Enugu': [
      'Enugu South',
      'Igbo-Eze South',
      'Enugu North',
      'Nkanu',
      'Udi Agwu',
      'Oji-River',
      'Ezeagu',
      'IgboEze North',
      'Isi-Uzo',
      'Nsukka',
      'Igbo-Ekiti',
      'Uzo-Uwani',
      'Enugu East',
      'Aninri',
      'Nkanu East',
      'Udenu',
    ],
    'Gombe': [
      'Akko',
      'Balanga',
      'Billiri',
      'Dukku',
      'Kaltungo',
      'Kwami',
      'Shomgom',
      'Funakaye',
      'Gombe',
      'Nafada/Bajoga',
      'Yamaltu/Delta',
    ],
    'Imo': [
      'Aboh-Mbaise',
      'Ahiazu-Mbaise',
      'Ehime-Mbano',
      'Ezinihitte',
      'Ideato North',
      'Ideato South',
      'Ihitte/Uboma',
      'Ikeduru',
      'Isiala Mbano',
      'Isu',
      'Mbaitoli',
      'Ngor-Okpala',
      'Njaba',
      'Nwangele',
      'Nkwerre',
      'Obowo',
      'Oguta',
      'Ohaji/Egbema',
      'Okigwe',
      'Orlu',
      'Orsu',
      'Oru East',
      'Oru West',
      'Owerri-Municipal',
      'Owerri North',
      'Owerri West',
    ],
    'Jigawa': [
      'Auyo',
      'Babura',
      'Birni Kudu',
      'Biriniwa',
      'Buji',
      'Dutse',
      'Gagarawa',
      'Garki',
      'Gumel',
      'Guri',
      'Gwaram',
      'Gwiwa',
      'Hadejia',
      'Jahun',
      'Kafin Hausa',
      'Kaugama Kazaure',
      'Kiri Kasamma',
      'Kiyawa',
      'Maigatari',
      'Malam Madori',
      'Miga',
      'Ringim',
      'Roni',
      'Sule-Tankarkar',
      'Taura',
      'Yankwashi',
    ],
    'Kaduna': [
      'Birni-Gwari',
      'Chikun',
      'Giwa',
      'Igabi',
      'Ikara',
      'jaba',
      'Jema\'a',
      'Kachia',
      'Kaduna North',
      'Kaduna South',
      'Kagarko',
      'Kajuru',
      'Kaura',
      'Kauru',
      'Kubau',
      'Kudan',
      'Lere',
      'Makarfi',
      'Sabon-Gari',
      'Sanga',
      'Soba',
      'Zango-Kataf',
      'Zaria',
    ],
    'Kano': [
      'Ajingi',
      'Albasu',
      'Bagwai',
      'Bebeji',
      'Bichi',
      'Bunkure',
      'Dala',
      'Dambatta',
      'Dawakin Kudu',
      'Dawakin Tofa',
      'Doguwa',
      'Fagge',
      'Gabasawa',
      'Garko',
      'Garum',
      'Mallam',
      'Gaya',
      'Gezawa',
      'Gwale',
      'Gwarzo',
      'Kabo',
      'Kano Municipal',
      'Karaye',
      'Kibiya',
      'Kiru',
      'kumbotso',
      'Ghari',
      'Kura',
      'Madobi',
      'Makoda',
      'Minjibir',
      'Nasarawa',
      'Rano',
      'Rimin Gado',
      'Rogo',
      'Shanono',
      'Sumaila',
      'Takali',
      'Tarauni',
      'Tofa',
      'Tsanyawa',
      'Tudun Wada',
      'Ungogo',
      'Warawa',
      'Wudil',
    ],
    'Katsina': [
      'Bakori',
      'Batagarawa',
      'Batsari',
      'Baure',
      'Bindawa',
      'Charanchi',
      'Dandume',
      'Danja',
      'Dan Musa',
      'Daura',
      'Dutsi',
      'Dutsin-Ma',
      'Faskari',
      'Funtua',
      'Ingawa',
      'Jibia',
      'Kafur',
      'Kaita',
      'Kankara',
      'Kankia',
      'Katsina',
      'Kurfi',
      'Kusada',
      'Mai\'Adua',
      'Malumfashi',
      'Mani',
      'Mashi',
      'Matazuu',
      'Musawa',
      'Rimi',
      'Sabuwa',
      'Safana',
      'Sandamu',
      'Zango',
    ],
    'Kebbi': [
      'Aleiro',
      'Arewa-Dandi',
      'Argungu',
      'Augie',
      'Bagudo',
      'Birnin Kebbi',
      'Bunza',
      'Dandi',
      'Fakai',
      'Gwandu',
      'Jega',
      'Kalgo',
      'Koko/Besse',
      'Maiyama',
      'Ngaski',
      'Sakaba',
      'Shanga',
      'Suru',
      'Wasagu/Danko',
      'Yauri',
      'Zuru',
    ],
    'Kogi': [
      'Adavi',
      'Ajaokuta',
      'Ankpa',
      'Bassa',
      'Dekina',
      'Ibaji',
      'Idah',
      'Igalamela-Odolu',
      'Ijumu',
      'Kabba/Bunu',
      'Lokoja',
      'Mopa-Muro',
      'Ofu',
      'Ogori/Mangongo',
      'Okehi',
      'Okene',
      'Olamabolo',
      'Omala',
      'Yagba East',
      'Yagba West',
    ],
    'Kwara': [
      'Asa',
      'Baruten',
      'Edu',
      'Ekiti',
      'Ifelodun',
      'Ilorin East',
      'Ilorin West',
      'Irepodun',
      'Isin',
      'Kaiama',
      'Moro',
      'Offa',
      'Oke-Ero',
      'Oyun',
      'Pategi',
    ],
    'Lagos': [
      'Agege',
      'Ajeromi-Ifelodun',
      'Alimosho',
      'Amuwo-Odofin',
      'Apapa',
      'Badagry',
      'Epe',
      'Eti-Osa',
      'Ibeju/Lekki',
      'Ifako-Ijaye',
      'Ikeja',
      'Ikorodu',
      'Kosofe',
      'Lagos Island',
      'Lagos Mainland',
      'Mushin',
      'Ojo',
      'Oshodi-Isolo',
      'Shomolu',
      'Surulere',
    ],
    'Nasarawa': [
      'Akwanga',
      'Awe',
      'Doma',
      'Karu',
      'Keana',
      'Keffi',
      'Kokona',
      'Lafia',
      'Nasarawa',
      'Nasarawa-Eggon',
      'Obi',
      'Toto',
      'Wamba',
    ],
    'Niger': [
      'Agaie',
      'Agwara',
      'Bida',
      'Borgu',
      'Bosso',
      'Chanchaga',
      'Edati',
      'Gbako',
      'Gurara',
      'Katcha',
      'Kontagora',
      'Lapai',
      'Lavun',
      'Magama',
      'Mariga',
      'Mashegu',
      'Mokwa',
      'Muya',
      'Pailoro',
      'Rafi',
      'Rijau',
      'Shiroro',
      'Suleja',
      'Tafa',
      'Wuse',
    ],
    'Ogun': [
      'Abeokuta North',
      'Abeokuta South',
      'Ado-Odo/Ota',
      'Egbado North',
      'Egbado South',
      'Ewekoro',
      'Ifo',
      'Ijebu East',
      'Ijebu North',
      'Ijebu North East',
      'Ijebu Ode',
      'Ikenne',
      'Imeko-Afon',
      'Ipokia',
      'Obafemi-Owode',
      'Ogun Waterside',
      'Odeda',
      'Odogbolu',
      'Remo North',
      'Shagamu',
    ],
    'Ondo': [
      'Akoko North East',
      'Akoko North West',
      'Akoko South Akure East',
      'Akoko South West',
      'Akure North',
      'Akure South',
      'Ese-Odo',
      'Idanre',
      'Ifedore',
      'Ilaje',
      'Ile-Oluji',
      'Okeigbo',
      'Odigbo',
      'Okitipupa',
      'Ondo East',
      'Ondo West',
      'Ose',
      'Owo',
    ],
    'Osun': [
      'Aiyedaade',
      'Aiyedire',
      'Atakumosa East',
      'Atakumosa West',
      'Boluwaduro',
      'Boripe',
      'Ede North',
      'Ede South',
      'Egbedore',
      'Ejigbo',
      'Ifedayo',
      'Ifelodun',
      'Ilesha East',
      'Ilesha West',
      'Ila',
      'Ife Central',
      'Ife East',
      'Ife North',
      'Ife South',
      'Irepodun',
      'Irewole',
      'Isokan',
      'Iwo',
      'Obokun',
      'Odo-Otin',
      'Ola-Oluwa',
      'Olorunda',
      'Oriade',
      'Orolu',
      'Osogbo',
    ],
    'Oyo': [
      'Afijio',
      'Akinyele',
      'Atiba',
      'Atigbo',
      'Egbeda',
      'Ibadan Central',
      'Ibadan North',
      'Ibadan North East',
      'Ibadan North West',
      'Ibadan South East',
      'Ibadan South West',
      'Ibarapa Central',
      'Ibarapa East',
      'Ibarapa North',
      'Ido',
      'Irepo',
      'Iseyin',
      'Itesiwaju',
      'Iwajowa',
      'Kajola',
      'Lagelu Ogbomosho North',
      'Ogbomosho South',
      'Ogo Oluwa',
      'Olorunsogo',
      'Oluyole',
      'Ona-Ara',
      'Orelope',
      'Ori Ire',
      'Oyo East',
      'Oyo West',
      'Saki East',
      'Saki West',
      'Surulere',
    ],
    'Plateau': [
      'Barkin Ladi',
      'Bassa',
      'Bokkos',
      'Jos East',
      'Jos North',
      'Jos South',
      'Kanam',
      'Kanke',
      'Langtang North',
      'Langtang South',
      'Mangu',
      'Mikang',
      'Pankshin',
      'Qua\'an Pan',
      'Riyom',
      'Shendam',
      'Wase',
    ],
    'Rivers': [
      'Abua/Odual',
      'Ahoada East',
      'Ahoada West',
      'Akuku Toru',
      'Andoni',
      'Asari-Toru',
      'Bonny',
      'Degema',
      'Emohua',
      'Eleme',
      'Etche',
      'Gokana',
      'Ikwerre',
      'Khana',
      'Obio/Akpor',
      'Ogba/Egbema/Ndoni',
      'Ogu/Bolo',
      'Okrika',
      'Omumma',
      'Opobo/Nkoro',
      'Oyigbo',
      'Port-Harcourt',
      'Tai',
    ],
    'Sokoto': [
      'Binji',
      'Bodinga',
      'Dange-shuni',
      'Gada',
      'Goronyo',
      'Gudu',
      'Gwadabawa',
      'Illela',
      'Isa',
      'Kware',
      'kebbe',
      'Rabah',
      'Sabon birni',
      'Shagari',
      'Silame',
      'Sokoto North',
      'Sokoto South',
      'Tambuwal',
      'Tangaza',
      'Tureta',
      'Wamako',
      'Wurno',
      'Yabo',
    ],
    'Taraba': [
      'Ardo-kola',
      'Bali',
      'Donga',
      'Gashaka',
      'Gassol',
      'Ibi',
      'Jalingo',
      'KarimLamido',
      'Kurmi',
      'Lau',
      'Sardauna',
      'Takum',
      'Ussa',
      'Wukari',
      'Yorro',
      'Zing',
    ],
    'Yobe': [
      'Bade',
      'Bursari',
      'Damaturu',
      'Fika',
      'Fune',
      'Geidam',
      'Gujba',
      'Gulani',
      'Jakusko',
      'Karasuwa',
      'Karawa',
      'Machina',
      'Nangere',
      'Nguru Potiskum',
      'Tarmua',
      'Yunusari',
      'Yusufari',
    ],
    'Zamfara': [
      'Anka',
      'Bakura',
      'Birnin Magaji',
      'Bukkuyum',
      'Bungudu',
      'Gummi',
      'Gusau',
      'Kaura',
      'Namoda',
      'Maradun',
      'Maru',
      'Shinkafi',
      'Talata Mafara',
      'Tsafe',
      'Zurmi',
    ],
    'Federal Capital Territory': [
      'Abaji',
      'Abuja Municipal',
      'Bwari',
      'Gwagwalada',
      'Kuje',
      'Kwali',
    ],
  };
  bool isFetchingLocation = false;
  @override
  void initState() {
    super.initState();
    states.sort();
    selectedState = null;
    cities = [];
    selectedCity = null;
    _emailController.text = FirebaseAuth.instance.currentUser!.email!;
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final fsDoc = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(user.uid)
        .get();

    if (fsDoc.exists) {
      final map = fsDoc.data()?['contact_data'] as Map<String, dynamic>?;
      if (map != null) {
        _emailController.text = map['email'] ?? _emailController.text;
        _phoneController.text = map['phone'] ?? '';
        selectedState = map['state'];
        if (selectedState != null) {
          updateCities(selectedState!);
        }
        selectedCity = map['city'];
        _addressController.text = map['address'] ?? '';
        setState(() {});
      }
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (userDoc.exists) {
      final data = userDoc.data() ?? {};
      _ninController.text = data['nin'] ?? _ninController.text;
      _dobController.text = data['dob'] ?? _dobController.text;

      final Map<String, dynamic>? userAddress =
          data['address'] as Map<String, dynamic>?;
      if (userAddress != null) {
        final street = userAddress['street'] as String?;
        final city = userAddress['city'] as String?;
        final state = userAddress['state'] as String?;

        if (street != null && street.isNotEmpty) {
          _addressController.text = street;
        }
        if (state != null && state.isNotEmpty) {
          selectedState = state;
          updateCities(state);
        }
        if (city != null && city.isNotEmpty) {
          selectedCity = city;
        }
      }

      setState(() {});
    }
  }

  bool isLoading = false;

  Future<void> _saveData() async {
    setState(() {
      isLoading = true;
    });
    if (_emailController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _ninController.text.isEmpty ||
        _dobController.text.isEmpty ||
        selectedState == null ||
        selectedCity == null ||
        _addressController.text.isEmpty) {
      showSnackBar(context, "Please fill all fields", Colors.red);
      setState(() {
        isLoading = false;
      });
      return;
    }

    if (_phoneController.text.length != 11 ||
        !_phoneController.text.startsWith('0')) {
      showSnackBar(
        context,
        'Phone number must start with 0 and be 11 digits',
        Colors.red,
      );
      setState(() {
        isLoading = false;
      });
      return;
    }

    if (_ninController.text.length != 11) {
      showSnackBar(
        context,
        'NIN must be 11 digits',
        Colors.red,
      );
      setState(() {
        isLoading = false;
      });
      return;
    }

    final code = generateSixDigitCode();
    final map = {
      'email': _emailController.text,
      'phone': _phoneController.text,
      'state': selectedState,
      'city': selectedCity,
      'address': _addressController.text,
      'postal': code,
    };
    final user = FirebaseAuth.instance.currentUser;

    await FirebaseFirestore.instance
        .collection('businesses')
        .doc(user!.uid)
        .set({'contact_data': map, 'contact_fixed': true}, SetOptions(merge: true));

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'nin': _ninController.text,
      'dateOfBirth': _dobController.text,
      'address': {
        'street': _addressController.text,
        'city': selectedCity,
        'state': selectedState,
      },
    }, SetOptions(merge: true));
    setState(() {
      isLoading = false;
    });
    Navigator.pop(context);
  }

  int generateSixDigitCode() {
    final random = Random();
    return 100000 + random.nextInt(900000);
  }

  void updateCities(String state) {
    setState(() {
      cities = stateToCities[state] ?? [];
      cities.sort();
      selectedCity = null;
    });
  }

  Future<void> autoFetchLocation() async {
    // Privacy consent gate — location
    final prefs = await SharedPreferences.getInstance();
    final alreadyConsented = prefs.getBool('privacy_consent_location') ?? false;
    if (!alreadyConsented) {
      if (!mounted) return;
      final result = await showPermissionExplanationSheet(
        context,
        title: 'Location Permission Required',
        explanation:
            'PadiPay needs access to your location to auto-fill your business address. Your location data is used only for this purpose and is not shared with third parties.',
      );
      if (result != true) return;
      await prefs.setBool('privacy_consent_location', true);
    }
    setState(() {
      isFetchingLocation = true;
    });
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        showSnackBar(
          context,
          "Location permission was previously denied",
          Colors.red,
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      showSnackBar(
        context,
        'Location permissions are permanently denied, opening app settings...',
        Colors.red,
      );
      await Geolocator.openAppSettings();
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String? country = place.country;
        String? state = place.administrativeArea;
        String? city =
            place.locality ?? place.subAdministrativeArea ?? place.subLocality;
        String address = '${place.street ?? ''}, ${place.postalCode ?? ''}'
            .trim();

        if (country == 'Nigeria' || country == null) {
          // Assume Nigeria if not specified
          if (state != null) {
            String normalizedState = state.trim().toLowerCase();
            String? matchedState = states.firstWhere(
              (s) =>
                  s.toLowerCase() == normalizedState ||
                  s.toLowerCase().contains(normalizedState),
              orElse: () => '',
            );
            if (matchedState.isNotEmpty) {
              setState(() {
                selectedState = matchedState;
              });
              updateCities(matchedState);
              if (city != null) {
                String normalizedCity = city.trim().toLowerCase();
                String? matchedCity = cities.firstWhere(
                  (c) =>
                      c.toLowerCase() == normalizedCity ||
                      c.toLowerCase().contains(normalizedCity),
                  orElse: () => '',
                );
                if (matchedCity.isNotEmpty) {
                  setState(() {
                    selectedCity = matchedCity;
                  });
                }
              }
            } else {
              // If no match, still set as custom
              setState(() {
                selectedState = state;
              });
            }
          }
          setState(() {
            _addressController.text = address.isNotEmpty ? address : '';
          });
        } else {
          showSnackBar(context, "You are not in Nigeria", Colors.red);
        }
      }
    } catch (e) {
      showSnackBar(context, 'Failed to fetch location: $e', Colors.red);
    } finally {
      setState(() {
        isFetchingLocation = false;
      });
    }
  }

  void _showSelectionBottomSheet({
    required String title,
    required List<String> items,
    required Function(String) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: _SelectionBottomSheetContent(
                title: title,
                items: items,
                onSelected: (value) {
                  onSelected(value);
                  Navigator.pop(context);
                },
                scrollController: scrollController,
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.arrow_back_ios,
                          color: Colors.black.withValues(alpha: 0.6),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Text(
                  "Contact & Address Setup",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                SizedBox(height: 15),
                Text(
                  textAlign: TextAlign.left,
                  "Enter your phone number, email, and address information so we can verify your identity and reach you when needed.",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade500,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 30),
                Text(
                  "Contact Information",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Email",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  controller: _emailController,
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "Enter email",
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.transparent),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "NIN",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                  controller: _ninController,
                  decoration: InputDecoration(
                    counterText: "",
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "Enter 11-digit NIN",
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.transparent),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Date of Birth (YYYY-MM-DD)",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.number,
                  controller: _dobController,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    DateOfBirthFormatter(),
                  ],
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "YYYY-MM-DD",
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.transparent),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Phone Number",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                  controller: _phoneController,
                  decoration: InputDecoration(
                    counterText: "",
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "Enter phone number",
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.transparent),
                    ),
                  ),
                ),
                SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Address Information",
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    isFetchingLocation
                        ? Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: SizedBox(
                              height: 30,
                              width: 30,
                              child: CircularProgressIndicator(
                                color: primaryColor,
                              ),
                            ),
                          )
                        : InkWell(
                            onTap: autoFetchLocation,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 15.0),
                              child: Icon(
                                Icons.location_on,
                                color: primaryColor,
                                size: 25,
                              ),
                            ),
                          ),
                  ],
                ),
                SizedBox(height: 20),
                Text(
                  "Country",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                Container(
                  width: MediaQuery.of(context).size.width,
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    selectedCountry,
                    style: GoogleFonts.inter(fontSize: 14),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "State",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    _showSelectionBottomSheet(
                      title: 'Select State',
                      items: states,
                      onSelected: (value) {
                        setState(() {
                          selectedState = value;
                        });
                        updateCities(value);
                      },
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          selectedState ?? 'Select State',
                          style: GoogleFonts.inter(
                            color: selectedState != null
                                ? Colors.black
                                : Colors.grey.shade400,
                            fontSize: 14,
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "City",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                GestureDetector(
                  onTap: cities.isNotEmpty
                      ? () {
                          _showSelectionBottomSheet(
                            title: 'Select City',
                            items: cities,
                            onSelected: (value) {
                              setState(() {
                                selectedCity = value;
                              });
                            },
                          );
                        }
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          selectedCity ?? 'Select City',
                          style: GoogleFonts.inter(
                            color: selectedCity != null
                                ? Colors.black
                                : Colors.grey.shade400,
                            fontSize: 14,
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Address",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.streetAddress,
                  controller: _addressController,
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "Enter address",
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.transparent),
                    ),
                  ),
                ),
                SizedBox(height: 40),

                isLoading
                    ? Center(child: CircularProgressIndicator(color: primaryColor))
                    : GestureDetector(
                        onTap: _saveData,
                        child: Container(
                          alignment: Alignment.center,
                          padding: EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 16,
                          ),
                          width: MediaQuery.of(context).size.width,
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "Save",
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionBottomSheetContent extends StatefulWidget {
  final String title;
  final List<String> items;
  final Function(String) onSelected;
  final ScrollController scrollController;

  const _SelectionBottomSheetContent({
    required this.title,
    required this.items,
    required this.onSelected,
    required this.scrollController,
  });

  @override
  _SelectionBottomSheetContentState createState() =>
      _SelectionBottomSheetContentState();
}

class _SelectionBottomSheetContentState
    extends State<_SelectionBottomSheetContent> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchController.addListener(_filterItems);
  }

  void _filterItems() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = widget.items
          .where((item) => item.toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            widget.title,
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search...',
              hintStyle: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            itemCount: _filteredItems.length,
            itemBuilder: (context, index) {
              final item = _filteredItems[index];
              return ListTile(
                title: Text(item, style: GoogleFonts.inter(fontSize: 14)),
                onTap: () => widget.onSelected(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class DateOfBirthFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text.replaceAll('-', '');
    if (newText.length > 8) return oldValue;

    String formatted = '';
    // Year (positions 0-3)
    if (newText.isNotEmpty) formatted += newText.substring(0, 1);
    if (newText.length >= 2) formatted += newText.substring(1, 2);
    if (newText.length >= 3) formatted += newText.substring(2, 3);
    if (newText.length >= 4) formatted += newText.substring(3, 4);
    if (newText.length >= 5) formatted += '-';
    // Month (positions 4-5)
    if (newText.length >= 5) formatted += newText.substring(4, 5);
    if (newText.length >= 6) formatted += newText.substring(5, 6);
    if (newText.length >= 7) formatted += '-';
    // Day (positions 6-7)
    if (newText.length >= 7) formatted += newText.substring(6, 7);
    if (newText.length >= 8) formatted += newText.substring(7, 8);

    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}