import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padi_pay_business/utils.dart';

class RepDetails extends StatefulWidget {
  const RepDetails({super.key});

  @override
  State<RepDetails> createState() => _RepDetailsState();
}

class _RepDetailsState extends State<RepDetails> {
  bool soleDirector = true;
  List<GlobalKey<_DirectorFormState>> directorKeys = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
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
      final map = fsDoc.data()?['rep_data'] as Map<String, dynamic>?;
      if (map != null) {
        soleDirector = map['sole'] ?? true;
        if (!soleDirector) {
          final directors = map['directors'] as List<dynamic>;
          setState(() {
            for (var _ in directors) {
              directorKeys.add(GlobalKey<_DirectorFormState>());
            }
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            for (int i = 0; i < directors.length; i++) {
              final d = directors[i] as Map<String, dynamic>;
              final state = directorKeys[i].currentState;
              if (state != null) {
                state.selectedRole = d['role'];
                state.roleController.text = d['role'] ?? '';
                state.selectedTitle = d['title'];
                state.titleController.text = d['title'] ?? '';
                state.firstNameController.text = d['firstName'] ?? '';
                state.lastNameController.text = d['lastName'] ?? '';
                state.emailController.text = d['email'] ?? '';
                state.bvnController.text = d['bvn'] ?? '';
                state.percentageController.text = d['percentage'] ?? '';
                state.selectedDob = d['dob'] != null
                    ? DateTime.parse(d['dob'])
                    : null;
                state.dobController.text = d['dob'] ?? '';
                state.selectedNationality = d['nationality'];
                state.nationalityController.text = d['nationality'] ?? '';
                state.selectedCountry = d['country'];
                state.countryController.text = d['country'] ?? '';
                state.selectedState = d['state'];
                state.stateController.text = d['state'] ?? '';
                state.cityController.text = d['city'] ?? '';
              }
            }
            setState(() {});
          });
        }
        setState(() {});
      }
    }
  }

  Future<void> _saveData() async {
    setState(() {
      isLoading = true;
    });
    if (!soleDirector) {
      bool allFilled = true;
      for (var key in directorKeys) {
        final state = key.currentState;
        if (state != null) {
          if (state.selectedRole == null ||
              state.selectedTitle == null ||
              state.firstNameController.text.isEmpty ||
              state.lastNameController.text.isEmpty ||
              state.emailController.text.isEmpty ||
              state.bvnController.text.isEmpty ||
              state.percentageController.text.isEmpty ||
              state.selectedDob == null ||
              state.selectedNationality == null ||
              state.selectedCountry == null ||
              (state.selectedCountry == 'Nigeria' &&
                  state.selectedState == null) ||
              state.cityController.text.isEmpty) {
            allFilled = false;
            break;
          }
        }
      }
      if (!allFilled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all director fields')),
        );
        setState(() {
          isLoading = false;
        });
        return;
      }
    }

    final map = <String, dynamic>{
      'sole': soleDirector,
      'directors': <Map<String, dynamic>>[],
    };
    if (!soleDirector) {
      for (var key in directorKeys) {
        final state = key.currentState;
        if (state != null) {
          map['directors'].add(state.getData());
        }
      }
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }
    await FirebaseFirestore.instance.collection('businesses').doc(user.uid).set(
      {'rep_data': map, 'rep_fixed': true},
      SetOptions(merge: true),
    );
    setState(() {
      isLoading = false;
    });
    Navigator.pop(context);
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
                  "Representative Details",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                SizedBox(height: 15),
                Text(
                  textAlign: TextAlign.left,
                  "Confirm who manages this account",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade500,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 30),
                Text(
                  "Business Directors",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Are you the sole director of this business?",
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    FlutterSwitch(
                      width: 50.0,
                      height: 30.0,
                      toggleSize: 15.0,
                      value: soleDirector,
                      activeColor: Colors.blue,
                      inactiveColor: Colors.grey.shade300,
                      onToggle: (val) {
                        setState(() => soleDirector = val);
                      },
                    ),
                  ],
                ),
                if (!soleDirector) ...[
                  SizedBox(height: 20),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: directorKeys.length,
                    itemBuilder: (context, index) {
                      return DirectorForm(
                        key: directorKeys[index],
                        onRemove: () {
                          setState(() {
                            directorKeys.removeAt(index);
                          });
                        },
                      );
                    },
                  ),
                  SizedBox(height: 20),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        directorKeys.add(GlobalKey<_DirectorFormState>());
                      });
                    },
                    child: Container(
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: primaryColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "Add Director",
                        style: GoogleFonts.inter(
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 50),
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

const List<String> countries = [
  'Afghanistan',
  'Albania',
  'Algeria',
  'Andorra',
  'Angola',
  'Antigua and Barbuda',
  'Argentina',
  'Armenia',
  'Australia',
  'Austria',
  'Azerbaijan',
  'Bahamas',
  'Bahrain',
  'Bangladesh',
  'Barbados',
  'Belarus',
  'Belgium',
  'Belize',
  'Benin',
  'Bhutan',
  'Bolivia',
  'Bosnia and Herzegovina',
  'Botswana',
  'Brazil',
  'Brunei',
  'Bulgaria',
  'Burkina Faso',
  'Burundi',
  'Cabo Verde',
  'Cambodia',
  'Cameroon',
  'Canada',
  'Central African Republic',
  'Chad',
  'Chile',
  'China',
  'Colombia',
  'Comoros',
  'Congo, Democratic Republic of the',
  'Congo, Republic of the',
  'Costa Rica',
  "Cote d'Ivoire",
  'Croatia',
  'Cuba',
  'Cyprus',
  'Czechia',
  'Denmark',
  'Djibouti',
  'Dominica',
  'Dominican Republic',
  'Ecuador',
  'Egypt',
  'El Salvador',
  'Equatorial Guinea',
  'Eritrea',
  'Estonia',
  'Eswatini',
  'Ethiopia',
  'Fiji',
  'Finland',
  'France',
  'Gabon',
  'Gambia',
  'Georgia',
  'Germany',
  'Ghana',
  'Greece',
  'Grenada',
  'Guatemala',
  'Guinea',
  'Guinea-Bissau',
  'Guyana',
  'Haiti',
  'Honduras',
  'Hungary',
  'Iceland',
  'India',
  'Indonesia',
  'Iran',
  'Iraq',
  'Ireland',
  'Israel',
  'Italy',
  'Jamaica',
  'Japan',
  'Jordan',
  'Kazakhstan',
  'Kenya',
  'Kiribati',
  'Kosovo',
  'Kuwait',
  'Kyrgyzstan',
  'Laos',
  'Latvia',
  'Lebanon',
  'Lesotho',
  'Liberia',
  'Libya',
  'Liechtenstein',
  'Lithuania',
  'Luxembourg',
  'Madagascar',
  'Malawi',
  'Malaysia',
  'Maldives',
  'Mali',
  'Malta',
  'Marshall Islands',
  'Mauritania',
  'Mauritius',
  'Mexico',
  'Micronesia',
  'Moldova',
  'Monaco',
  'Mongolia',
  'Montenegro',
  'Morocco',
  'Mozambique',
  'Myanmar',
  'Namibia',
  'Nauru',
  'Nepal',
  'Netherlands',
  'New Zealand',
  'Nicaragua',
  'Niger',
  'Nigeria',
  'North Korea',
  'North Macedonia',
  'Norway',
  'Oman',
  'Pakistan',
  'Palau',
  'Palestine',
  'Panama',
  'Papua New Guinea',
  'Paraguay',
  'Peru',
  'Philippines',
  'Poland',
  'Portugal',
  'Qatar',
  'Romania',
  'Russia',
  'Rwanda',
  'Saint Kitts and Nevis',
  'Saint Lucia',
  'Saint Vincent and the Grenadines',
  'Samoa',
  'San Marino',
  'Sao Tome and Principe',
  'Saudi Arabia',
  'Senegal',
  'Serbia',
  'Seychelles',
  'Sierra Leone',
  'Singapore',
  'Slovakia',
  'Slovenia',
  'Solomon Islands',
  'Somalia',
  'South Africa',
  'South Korea',
  'South Sudan',
  'Spain',
  'Sri Lanka',
  'Sudan',
  'Suriname',
  'Sweden',
  'Switzerland',
  'Syria',
  'Taiwan',
  'Tajikistan',
  'Tanzania',
  'Thailand',
  'Timor-Leste',
  'Togo',
  'Tonga',
  'Trinidad and Tobago',
  'Tunisia',
  'Turkey',
  'Turkmenistan',
  'Tuvalu',
  'Uganda',
  'Ukraine',
  'United Arab Emirates',
  'United Kingdom',
  'United States of America',
  'Uruguay',
  'Uzbekistan',
  'Vanuatu',
  'Vatican City',
  'Venezuela',
  'Vietnam',
  'Yemen',
  'Zambia',
  'Zimbabwe',
];

const List<String> nigerianStates = [
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
  'Federal Capital Territory',
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
];

const List<String> roles = ['Director', 'Owner'];

const List<String> titles = [
  'VP',
  'CIO',
  'President',
  'COO',
  'CEO',
  'CFO.',
  'Treasurer',
  'Controller',
  'Manager',
  'Partner',
  'Member',
];

class DirectorForm extends StatefulWidget {
  const DirectorForm({super.key, required this.onRemove});

  final VoidCallback onRemove;

  @override
  State<DirectorForm> createState() => _DirectorFormState();
}

class _DirectorFormState extends State<DirectorForm> {
  String? selectedRole;
  String? selectedTitle;
  late TextEditingController firstNameController;
  late TextEditingController lastNameController;
  late TextEditingController emailController;
  late TextEditingController bvnController;
  late TextEditingController percentageController;
  late TextEditingController dobController;
  late TextEditingController nationalityController;
  late TextEditingController countryController;
  late TextEditingController stateController;
  late TextEditingController cityController;
  late TextEditingController roleController;
  late TextEditingController titleController;
  String? selectedNationality;
  String? selectedCountry;
  String? selectedState;
  DateTime? selectedDob;

  @override
  void initState() {
    super.initState();
    firstNameController = TextEditingController();
    lastNameController = TextEditingController();
    emailController = TextEditingController();
    bvnController = TextEditingController();
    percentageController = TextEditingController();
    dobController = TextEditingController();
    nationalityController = TextEditingController();
    countryController = TextEditingController(text: 'Nigeria');
    selectedCountry = 'Nigeria';
    stateController = TextEditingController();
    cityController = TextEditingController();
    roleController = TextEditingController();
    titleController = TextEditingController();
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    bvnController.dispose();
    percentageController.dispose();
    dobController.dispose();
    nationalityController.dispose();
    countryController.dispose();
    stateController.dispose();
    cityController.dispose();
    roleController.dispose();
    titleController.dispose();
    super.dispose();
  }

  Map<String, dynamic> getData() {
    return {
      'role': selectedRole,
      'title': selectedTitle,
      'firstName': firstNameController.text,
      'lastName': lastNameController.text,
      'dob': dobController.text,
      'email': emailController.text,
      'nationality': selectedNationality,
      'country': selectedCountry,
      'state': selectedState,
      'city': cityController.text,
      'bvn': bvnController.text,
      'percentage': percentageController.text,
    };
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
              return item.toLowerCase().contains(searchQuery.toLowerCase());
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
                            item,
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                          onTap: () {
                            onSelected(item);
                            controller.text = item;
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
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Director Details",
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              IconButton(
                icon: Icon(Icons.remove_circle_outline, color: Colors.red),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          SizedBox(height: 20),
          Text(
            "Role",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          SizedBox(height: 10),
          TextField(
            controller: roleController,
            readOnly: true,
            onTap: () {
              _showSearchablePicker(
                items: roles,
                selectedValue: selectedRole,
                onSelected: (value) {
                  setState(() {
                    selectedRole = value;
                  });
                },
                controller: roleController,
                title: 'Select Role',
              );
            },
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 10,
              ),
              hintText: "Select role",
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
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryColor, width: 1),
              ),
            ),
          ),
          SizedBox(height: 20),
          Text(
            "Title",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          SizedBox(height: 10),
          TextField(
            controller: titleController,
            readOnly: true,
            onTap: () {
              _showSearchablePicker(
                items: titles,
                selectedValue: selectedTitle,
                onSelected: (value) {
                  setState(() {
                    selectedTitle = value;
                  });
                },
                controller: titleController,
                title: 'Select Title',
              );
            },
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 10,
              ),
              hintText: "Select title",
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
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryColor, width: 1),
              ),
            ),
          ),
          SizedBox(height: 20),
          Text(
            "First Name",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          SizedBox(height: 10),
          TextField(
            controller: firstNameController,
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 10,
              ),
              hintText: "Enter first name",
              hintStyle: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryColor, width: 1),
              ),
            ),
          ),
          SizedBox(height: 20),
          Text(
            "Last Name",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          SizedBox(height: 10),
          TextField(
            controller: lastNameController,
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 10,
              ),
              hintText: "Enter last name",
              hintStyle: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryColor, width: 1),
              ),
            ),
          ),
          SizedBox(height: 20),
          Text(
            "Date of Birth",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          SizedBox(height: 10),
          TextField(
            controller: dobController,
            readOnly: true,
            onTap: () async {
              DateTime? picked = await showDatePicker(
                context: context,
                initialDate:
                    selectedDob ??
                    DateTime.now().subtract(Duration(days: 365 * 18)),
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
              if (picked != null && picked != selectedDob) {
                setState(() {
                  selectedDob = picked;
                  dobController.text = _formatDate(picked);
                });
              }
            },
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 10,
              ),
              hintText: "Select date of birth",
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
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryColor, width: 1),
              ),
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
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
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
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryColor, width: 1),
              ),
            ),
          ),
          SizedBox(height: 20),
          Text(
            "Nationality",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          SizedBox(height: 10),
          TextField(
            controller: nationalityController,
            readOnly: true,
            onTap: () {
              _showSearchablePicker(
                items: countries,
                selectedValue: selectedNationality,
                onSelected: (value) {
                  setState(() {
                    selectedNationality = value;
                  });
                },
                controller: nationalityController,
                title: 'Select Nationality',
              );
            },
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 10,
              ),
              hintText: "Select nationality",
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
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryColor, width: 1),
              ),
            ),
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
          TextField(
            controller: countryController,
            readOnly: true,
            onTap: () {
              _showSearchablePicker(
                items: countries,
                selectedValue: selectedCountry,
                onSelected: (value) {
                  setState(() {
                    selectedCountry = value;
                    selectedState = null;
                    stateController.clear();
                  });
                },
                controller: countryController,
                title: 'Select Country',
              );
            },
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 10,
              ),
              hintText: "Select country",
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
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryColor, width: 1),
              ),
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
          if (selectedCountry == 'Nigeria')
            TextField(
              controller: stateController,
              readOnly: true,
              onTap: () {
                _showSearchablePicker(
                  items: nigerianStates,
                  selectedValue: selectedState,
                  onSelected: (value) {
                    setState(() {
                      selectedState = value;
                    });
                  },
                  controller: stateController,
                  title: 'Select State',
                );
              },
              decoration: InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  vertical: 15,
                  horizontal: 10,
                ),
                hintText: "Select state",
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
                  borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: primaryColor, width: 1),
                ),
              ),
            )
          else
            TextField(
              controller: stateController,
              decoration: InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  vertical: 15,
                  horizontal: 10,
                ),
                hintText: "Enter state",
                hintStyle: GoogleFonts.inter(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: primaryColor, width: 1),
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
          TextField(
            controller: cityController,
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 10,
              ),
              hintText: "Enter city",
              hintStyle: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryColor, width: 1),
              ),
            ),
          ),
          SizedBox(height: 20),
          Text(
            "BVN",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          SizedBox(height: 10),
          TextField(
            controller: bvnController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 10,
              ),
              hintText: "Enter BVN",
              hintStyle: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryColor, width: 1),
              ),
            ),
          ),
          SizedBox(height: 20),
          Text(
            "Percentage Owned",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          SizedBox(height: 10),
          TextField(
            controller: percentageController,
            keyboardType: TextInputType.number,
            onChanged: (value) {
              double? num = double.tryParse(value);
              if (num != null && (num < 0 || num > 100)) {
                percentageController.text = value.substring(
                  0,
                  value.length - 1,
                );
              }
            },
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 10,
              ),
              hintText: "Enter percentage (0-100)",
              hintStyle: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryColor, width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}