import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

final Color mixedColor = Color(0xFFd98fd9); // bluish purple

class ProfilePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: 30),
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: AssetImage('assets/images/powerpay_logo.png'),
                    ),
                    SizedBox(height: 15),
                    Text(
                      'Eon Morgn',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 10),
              ListTile(
                leading: Icon(FontAwesomeIcons.scaleBalanced, color: mixedColor,),
                trailing: Icon(Icons.chevron_right, color: mixedColor,),
                title: Text('  Commissions'),
                onTap: () {},
              ),
              Container(height: 1, color: Colors.grey.shade300), // thin line with no spacing
              ListTile(
                leading: Icon(FontAwesomeIcons.fileInvoice, color: mixedColor,),
                trailing: Icon(Icons.chevron_right, color: mixedColor,),
                title: Text('  Commission Summary'),
                onTap: () {},
              ),
              Container(height: 1, color: Colors.grey.shade300),
              ListTile(
                leading: Icon(FontAwesomeIcons.userLock, color: mixedColor,),
                trailing: Icon(Icons.chevron_right, color: mixedColor,),
                title: Text('  Change Pin'),
                onTap: () {},
              ),
              Container(height: 1, color: Colors.grey.shade300),
              ListTile(
                leading: Icon(FontAwesomeIcons.userCheck, color: mixedColor,),
                trailing: Icon(Icons.chevron_right, color: mixedColor,),
                title: Text('  White List'),
                onTap: () {},
              ),
              Container(height: 1, color: Colors.grey.shade300),
              ListTile(
                leading: Icon(FontAwesomeIcons.addressCard, color: mixedColor,),
                trailing: Icon(Icons.chevron_right, color: mixedColor,),
                title: Text('  E-KYC'),
                onTap: () {},
              ),
              Container(height: 1, color: Colors.grey.shade300),
              ListTile(
                leading: Icon(FontAwesomeIcons.mapLocation, color: mixedColor,),
                trailing: Icon(Icons.chevron_right, color: mixedColor,),
                title: Text('  Store Location'),
                onTap: () {},
              ),
              Container(height: 1, color: Colors.grey.shade300),
              ListTile(
                leading: Icon(FontAwesomeIcons.cloudUploadAlt, color: mixedColor,),
                trailing: Icon(Icons.chevron_right, color: mixedColor,),
                title: Text('  Check For Updates'),
                onTap: () {},
              ),
              Container(height: 1, color: Colors.grey.shade300),
              ListTile(
                leading: Icon(FontAwesomeIcons.paperclip, color: mixedColor,),
                trailing: Icon(Icons.chevron_right, color: mixedColor,),
                title: Text('  Document Upload'),
                onTap: () {},
              ),
              Container(height: 1, color: Colors.grey.shade300),
              ListTile(
                leading: Icon(FontAwesomeIcons.rightFromBracket, color: mixedColor,),
                trailing: Icon(Icons.chevron_right, color: mixedColor,),
                title: Text('  Logout'),
                onTap: () {},
              ),
              Container(height: 1, color: Colors.grey.shade300),
              ListTile(
                leading: Icon(FontAwesomeIcons.powerOff, color: mixedColor,),
                trailing: Icon(Icons.chevron_right, color: mixedColor,),
                title: Text('  Logout From All Devices'),
                onTap: () {},
              ),
              Container(height: 1, color: Colors.grey.shade300),
              SizedBox(height: 15),
              // Copyright text at the end of scroll
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  'Copyrights © All Rights Reserved',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
