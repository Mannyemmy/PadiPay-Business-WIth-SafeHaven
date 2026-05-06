import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padi_pay_business/home_pages/home_page.dart';
import 'package:padi_pay_business/utils.dart';

class BusinessInformation extends StatefulWidget {
  const BusinessInformation({super.key});

  @override
  State<BusinessInformation> createState() => _BusinessInformationState();
}

class _BusinessInformationState extends State<BusinessInformation> {
  String? selectedIndustry;
  String? selectedRegType;
  DateTime? selectedDate;
  late TextEditingController _dateController;
  late TextEditingController _industryController;
  late TextEditingController _regTypeController;
  late TextEditingController _nameController;
  late TextEditingController _bvnController;
  late TextEditingController _descController;
  late TextEditingController _bizAddressController;
  late TextEditingController _rcBnController;
  String? selectedRegState;
  List<String> regCities = [];
  String? selectedRegCity;
  late TextEditingController _regStateController;
  late TextEditingController _regCityController;
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

  @override
  void initState() {
    super.initState();
    states.sort();
    _rcBnController = TextEditingController();
    _dateController = TextEditingController();
    _industryController = TextEditingController();
    _regTypeController = TextEditingController();
    _nameController = TextEditingController();
    _bvnController = TextEditingController();
    _descController = TextEditingController();
    _bizAddressController = TextEditingController();
    _regStateController = TextEditingController();
    _regCityController = TextEditingController();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final fsDoc = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(user.uid)
        .get();

    // Always fetch BVN from verified source in users collection
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userMap = userDoc.exists
          ? (userDoc.data() ?? <String, dynamic>{})
          : <String, dynamic>{};
      final qoreData = userMap['qoreIdData'] as Map<String, dynamic>?;

      // Primary: bvnVerificationNoFace.bvn (set by verifyBvnNoFace)
      final bvnVerif =
          qoreData?['bvnVerificationNoFace'] as Map<String, dynamic>?;
      final verifiedBvn = bvnVerif?['bvn']?.toString();

      // Fallback: root-level bvn field
      final rootBvn = userMap['bvn']?.toString();

      _bvnController.text = (verifiedBvn != null && verifiedBvn.isNotEmpty)
          ? verifiedBvn
          : (rootBvn ?? '');
    } catch (e) {
      _bvnController.text = '';
    }

    if (fsDoc.exists) {
      final map = fsDoc.data()?['business_data'] as Map<String, dynamic>?;
      if (map != null) {
        _nameController.text = map['name'] ?? '';
        _rcBnController.text = map['rcBn'] ?? ''; // ADD THIS
        _nameController.text = map['name'] ?? '';
        selectedIndustry = map['industry'];
        _industryController.text = _format(map['industry'] ?? '');
        selectedRegType = map['regType'];
        _regTypeController.text = _format(map['regType'] ?? '');
        if (map['regDate'] != null) {
          selectedDate = DateTime.tryParse(map['regDate']);
          _dateController.text = map['regDate'];
        }
        selectedRegState = map['regState'];
        if (selectedRegState != null) updateRegCities(selectedRegState!);
        selectedRegCity = map['regCity'];
        _bizAddressController.text = map['bizAddress'] ?? '';
        _regStateController.text = selectedRegState ?? '';
        _regCityController.text = selectedRegCity ?? '';
        setState(() {});
      } else {
        selectedRegType = "Business_Name";
        _regTypeController.text = _format("Business_Name");
        setState(() {});
      }
    } else {
      selectedRegType = "Business_Name";
      _regTypeController.text = _format("Business_Name");
      setState(() {});
    }
  }
  Future<void> _showSuccessModal() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE6F4EA),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Color(0xFF34A853),
                    size: 44,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Account Upgraded!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'You can now fully enjoy all Padi Pay features including higher transfer limits, bill payments, and much more.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      navigateTo(context, HomePage());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Go to Dashboard',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool isLoading = false;

  Future<void> _saveData() async {
    if (_nameController.text.isEmpty ||
        _bvnController.text.isEmpty ||
        selectedIndustry == null ||
        _rcBnController.text.isEmpty ||
        selectedRegType == null ||
        selectedDate == null ||
        selectedRegState == null ||
        selectedRegCity == null ||
        _bizAddressController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    if (_bvnController.text.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('BVN must be exactly 11 digits')),
      );
      return;
    }

    setState(() => isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => isLoading = false);
      return;
    }

    try {
      final map = {
        'name': _nameController.text,
        'bvn': _bvnController.text,
        'industry': selectedIndustry,
        'regType': selectedRegType,
        'rcBn': _rcBnController.text, // ADD THIS

        'regDate': _dateController.text,
        'regState': selectedRegState,
        'regCity': selectedRegCity,
        'bizAddress': _bizAddressController.text,
      };

      // 1. Save business_data first
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(user.uid)
          .set({
            'business_data': map,
            'business_fixed': true,
          }, SetOptions(merge: true));

      // 2. Check if business virtual account already exists
      final bizDoc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(user.uid)
          .get();
      final existingVa =
          (bizDoc.data()?['safehavenData']
              as Map<String, dynamic>?)?['virtualAccount'];

      if (existingVa != null) {
        // Already has a business account, skip creation
        if (mounted) Navigator.pop(context);
        return;
      }

      // 3. Fetch user data needed for the API call
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? <String, dynamic>{};

      final String email = userData['email']?.toString() ?? '';
      String phone = userData['phone']?.toString() ?? '';
      // Normalize phone to 0XXXXXXXXXX format
      if (phone.startsWith('+234')) phone = '0${phone.substring(4)}';
      if (phone.startsWith('234') && phone.length == 13)
        phone = '0${phone.substring(3)}';

      // 4. Get identityId from user's safehaven verification (set during BVN OTP flow)
      // 4. Get identityId from safehavenUserSetup collection
      final safehavenSetupDoc = await FirebaseFirestore.instance
          .collection('safehavenUserSetup')
          .doc(user.uid)
          .get();
      final safehavenSetupData =
          safehavenSetupDoc.data() ?? <String, dynamic>{};
      final identityVerification =
          safehavenSetupData['identityVerification'] as Map<String, dynamic>?;
      final String? identityId = identityVerification?['identityId']
          ?.toString();

      if (identityId == null || identityId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Identity not verified yet. Please complete BVN verification first.',
            ),
          ),
        );
        setState(() => isLoading = false);
        return;
      }

      if (email.isEmpty || phone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Missing email or phone number on your profile.'),
          ),
        );
        setState(() => isLoading = false);
        return;
      }

      // 5. Call cloud function to create business sub-account
      final result = await FirebaseFunctions.instance
          .httpsCallable('safehavenCreateBusinessSubAccount')
          .call({
            'phoneNumber': phone,
            'emailAddress': email,
            'externalReference': user.uid,
            'identityType': 'vID',
            'identityId': identityId,
            'companyRegistrationNumber': _rcBnController
                .text, // WAS _nameController.text                .text, // RC/BN number — using business name as fallback; ideally a separate field
          });

      print('safehavenCreateBusinessSubAccount result: ${result.data}');

      // 6. Store result in businesses collection (function also does this server-side)
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(user.uid)
          .set({
            'safehavenData': {
              'virtualAccount': {'data': result.data},
            },
          }, SetOptions(merge: true));
  //set tier to 3
   await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
            'safehavenData': {
              'tier': 3,
            },
          }, SetOptions(merge: true));
     _showSuccessModal();
    } catch (e) {
      print('Error creating business account: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void updateRegCities(String state) {
    setState(() {
      regCities = stateToCities[state] ?? [];
      regCities.sort();
      selectedRegCity = null;
      _regCityController.text = '';
    });
  }

  @override
  void dispose() {
    _rcBnController.dispose();
    _dateController.dispose();
    _industryController.dispose();
    _regTypeController.dispose();
    _nameController.dispose();
    _bvnController.dispose();
    _descController.dispose();
    _bizAddressController.dispose();
    _regStateController.dispose();
    _regCityController.dispose();
    super.dispose();
  }

  String _format(String value) {
    var formatted = value.replaceAll('-', ' - ').replaceAll('_', ' ');
    formatted = formatted.replaceAllMapped(
      RegExp(r'(?<!^)([A-Z])'),
      (m) => ' ${m.group(0)}',
    );
    return formatted.trim();
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    return '$year-$month-$day';
  }

  void _showSearchablePicker({
    required List<String> items,
    required String? selectedValue,
    required Function(String?) onSelected,
    required TextEditingController controller,
    required String title,
    Function(String)? onSelectedExtra,
  }) {
    String searchQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            final filteredItems = items.where((item) {
              return _format(
                item,
              ).toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return Container(
              decoration: BoxDecoration(color: Colors.white),
              height: MediaQuery.of(context).size.height * 0.8,
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  TextField(
                    onChanged: (value) {
                      setBottomSheetState(() {
                        searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 15,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.all(0),
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return ListTile(
                          title: Text(
                            _format(item),
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                          onTap: () {
                            onSelected(item);
                            controller.text = _format(item);
                            if (onSelectedExtra != null) {
                              onSelectedExtra(item);
                            }
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
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
                  "Business Information",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                SizedBox(height: 15),
                Text(
                  textAlign: TextAlign.left,
                  "Provide the official details that defines your business",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade500,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 30),
                Text(
                  "Business Identification",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Business Name",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  textCapitalization: TextCapitalization.words,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                  controller: _nameController,
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "Enter business name",
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
                  "RC / BN Number",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.characters,
                  controller: _rcBnController,
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "Enter RC or BN number (e.g. RC1234567)",
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
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryColor, width: 1),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Business Bvn",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  // BVN is sourced from verified QoreID metadata and is not editable here
                  readOnly: true,
                  maxLength: 11,
                  controller: _bvnController,
                  decoration: InputDecoration(
                    counterText: "",
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "BVN (from verified ID)",
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
                  "Industry",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: _industryController,
                  readOnly: true,
                  onTap: () {
                    _showSearchablePicker(
                      items: industries,
                      selectedValue: selectedIndustry,
                      onSelected: (value) {
                        setState(() {
                          selectedIndustry = value;
                        });
                      },
                      controller: _industryController,
                      title: 'Select Industry',
                    );
                  },
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "Select industry",
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    suffixIcon: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey.shade600,
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
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryColor, width: 1),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Registration Type",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: _regTypeController,
                  readOnly: true,
                  onTap: () {
                    _showSearchablePicker(
                      items: regTypes,
                      selectedValue: selectedRegType,
                      onSelected: (value) {
                        setState(() {
                          selectedRegType = value;
                        });
                      },
                      controller: _regTypeController,
                      title: 'Select Registration Type',
                    );
                  },
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "Select registration type",
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    suffixIcon: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey.shade600,
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
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryColor, width: 1),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Date of Registration",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: _dateController,
                  readOnly: true,
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: Theme.of(
                              context,
                            ).colorScheme.copyWith(primary: primaryColor),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null && picked != selectedDate) {
                      setState(() {
                        selectedDate = picked;
                        _dateController.text = _formatDate(picked);
                      });
                    }
                  },
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "Select date of registration",
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    suffixIcon: Icon(
                      Icons.calendar_today_outlined,
                      color: Colors.grey.shade600,
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
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryColor, width: 1),
                    ),
                  ),
                ),
                SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Business Profile",
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),

                Text(
                  "Country of Operation",
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
                    "Nigeria",
                    style: GoogleFonts.inter(fontSize: 14),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Registered State",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: _regStateController,
                  readOnly: true,
                  onTap: () {
                    _showSearchablePicker(
                      items: states,
                      selectedValue: selectedRegState,
                      onSelected: (value) {
                        setState(() {
                          selectedRegState = value;
                        });
                      },
                      onSelectedExtra: updateRegCities,
                      controller: _regStateController,
                      title: 'Select State',
                    );
                  },
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "Select State",
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    suffixIcon: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey.shade600,
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
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryColor, width: 1),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Registered City",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: _regCityController,
                  readOnly: true,
                  onTap: regCities.isNotEmpty
                      ? () {
                          _showSearchablePicker(
                            items: regCities,
                            selectedValue: selectedRegCity,
                            onSelected: (value) {
                              setState(() {
                                selectedRegCity = value;
                              });
                            },
                            controller: _regCityController,
                            title: 'Select City',
                          );
                        }
                      : null,
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
                    hintText: "Select City",
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    suffixIcon: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey.shade600,
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
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: primaryColor, width: 1),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "Registered Address",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  keyboardType: TextInputType.streetAddress,
                  textInputAction: TextInputAction.done,
                  controller: _bizAddressController,
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
                    ? Center(
                        child: CircularProgressIndicator(color: primaryColor),
                      )
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

const List<String> industries = [
  "Agriculture-AgriculturalCooperatives",
  "Agriculture-AgriculturalServices",
  "Commerce-Automobiles",
  "Commerce-DigitalGoods",
  "Commerce-PhysicalGoods",
  "Commerce-RealEstate",
  "Commerce-DigitalServices",
  "Commerce-LegalServices",
  "Commerce-PhysicalServices",
  "Commerce-ProfessionalServices",
  "Commerce-OtherProfessionalServices",
  "Education-NurserySchools",
  "Education-PrimarySchools",
  "Education-SecondarySchools",
  "Education-TertiaryInstitutions",
  "Education-VocationalTraining",
  "Education-VirtualLearning",
  "Education-OtherEducationalServices",
  "Gaming-Betting",
  "Gaming-Lotteries",
  "Gaming-PredictionServices",
  "FinancialServices-FinancialCooperatives",
  "FinancialServices-CorporateServices",
  "FinancialServices-PaymentSolutionServiceProviders",
  "FinancialServices-Insurance",
  "FinancialServices-Investments",
  "FinancialServices-AgriculturalInvestments",
  "FinancialServices-Lending",
  "FinancialServices-BillPayments",
  "FinancialServices-Payroll",
  "FinancialServices-Remittances",
  "FinancialServices-Savings",
  "FinancialServices-MobileWallets",
  "Health-Gyms",
  "Health-Hospitals",
  "Health-Pharmacies",
  "Health-HerbalMedicine",
  "Health-Telemedicine",
  "Health-MedicalLaboratories",
  "Hospitality-Hotels",
  "Hospitality-Restaurants",
  "Nonprofits-ProfessionalAssociations",
  "Nonprofits-GovernmentAgencies",
  "Nonprofits-NGOs",
  "Nonprofits-PoliticalParties",
  "Nonprofits-ReligiousOrganizations",
  "Nonprofits-Leisure_And_Entertainment",
  "Nonprofits-Cinemas",
  "Nonprofits-Nightclubs",
  "Nonprofits-Events",
  "Nonprofits-Press_And_Media",
  "Nonprofits-RecreationCentres",
  "Nonprofits-Cinemas",
  "Nonprofits-StreamingServices",
  "Logistics-CourierServices",
  "Logistics-FreightServices",
  "Travel-Airlines",
  "Travel-Ridesharing",
  "Travel-TourServices",
  "Travel-Transportation",
  "Travel-TravelAgencies",
  "Utilities-CableTelevision",
  "Utilities-Electricity",
  "Utilities-GarbageDisposal",
  "Utilities-Internet",
  "Utilities-Telecoms",
  "Utilities-Water",
  "RetailWholesale",
  "Restaurants",
  "Construction",
  "Unions",
  "RealEstate",
  "FreelanceProfessional",
  "OtherProfessionalServices",
  "OnlineRetailer",
  "OtherEducationServices",
];

const List<String> regTypes = [
  "Business_Name",
  "Cooperative_Society",
  "Incorporated_Trustees",
  "Private_Incorporated",
  "Public_Incorporated",
  "Free_Zone",
  "GovPrivate_Incorporated_Gov",
];
