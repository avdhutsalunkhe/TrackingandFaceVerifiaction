import 'language_service.dart';

class AppTranslations {
  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // General & Auth
      'app_title': 'FieldStaff AI',
      'app_subtitle': 'Biometric & Geofence Attendance',
      'sign_in': 'Sign In',
      'login': 'Login',
      'employee_id': 'Employee ID / Admin ID',
      'password': 'Password',
      'current_password': 'Current Password',
      'new_password': 'New Password',
      'confirm_password': 'Confirm New Password',
      'please_enter_emp_id': 'Please enter Employee ID',
      'please_enter_password': 'Please enter password',
      'welcome': 'Welcome',
      'welcome_back': 'Welcome Back',
      'logout': 'Logout',
      'logout_confirm': 'Are you sure you want to log out?',
      'cancel': 'Cancel',
      'save': 'Save',
      'submit': 'Submit',
      'success': 'Success',
      'error': 'Error',
      'warning': 'Warning',
      'refresh': 'Refresh',
      'search': 'Search',
      'filter': 'Filter',
      'status': 'Status',
      'date': 'Date',
      'time': 'Time',
      'location': 'Location',
      'language': 'Language',
      'select_language': 'Select Language',
      'english': 'English',
      'marathi': 'मराठी',

      // Navigation & Titles
      'user_dashboard': 'Employee Dashboard',
      'admin_dashboard': 'Admin Dashboard',
      'mark_attendance': 'Mark Attendance',
      'verify_attendance': 'Biometric Verification',
      'attendance_history': 'Attendance History',
      'send_request': 'Send Regularization Request',
      'request_history': 'Request Status',
      'change_password': 'Change Password',
      'attendance_portal': 'Attendance Portal',

      // Greetings & Shifts
      'good_morning': 'Good Morning',
      'good_afternoon': 'Good Afternoon',
      'good_evening': 'Good Evening',
      'general_shift': 'General Shift',
      'flexible_shift': 'Flexible Shift',
      'regular_shift_hours': 'Regular Shift Hours',

      // Shift & Location Cards
      'todays_shift': "Today's Shift",
      'assigned': 'Assigned',
      'work_location': 'Work Location',
      'verified': 'Verified',
      'assigned_work_site': 'Assigned Work Site',

      // Main Button & Statuses
      'mark_attendance_btn': 'MARK ATTENDANCE',
      'attendance_recorded_btn': 'ATTENDANCE RECORDED ✓',
      'service_unavailable': 'The attendance service is temporarily unavailable.',
      'window_open_sub': 'Attendance window is open now.',
      'already_recorded_sub': 'Attendance already recorded.',
      'window_closed_sub': 'Attendance window closed.',
      'not_started_sub': 'Attendance has not started yet.',

      // Notifications / Countdown & Empty States
      'no_shift_assigned': 'No Shift Assigned',
      'no_shift_assigned_sub': 'You are not currently assigned to an active shift.',
      'no_punch_schedule': 'No Punch Schedule',
      'no_punch_schedule_sub': 'No punch periods scheduled for your shift today.',
      'server_unavailable_title': 'Attendance verification unavailable',
      'server_unavailable_sub': 'The attendance service is temporarily unavailable. Please try again later.',
      'starts_in_min': '🔔 Attendance starts in {min} min',
      'starts_in_less_min': '🔔 Attendance starts in less than 1 min',
      'get_ready': 'Get ready to mark your attendance.',
      'window_open_title': '🟢 Attendance is open now',
      'mark_now': 'You can mark your attendance.',
      'all_recorded_title': '✓ Attendance already recorded',
      'all_recorded_sub': 'Your attendance has been recorded for today.',
      'window_closed_title': 'Attendance window closed',
      'window_closed_desc': 'The attendance period for this shift has ended.',

      // Schedule Card
      'todays_schedule': "Today's Schedule",
      'periods_count': '{count} Periods',
      'open_now': 'Open Now',
      'closed': 'Closed',
      'upcoming': 'Upcoming',
      'completed': 'Recorded ✓',

      // Requests & Issues
      'facing_issues': 'Facing issues? Submit Attendance Request',

      // Dashboard Elements
      'current_shift': 'Current Shift',
      'today_attendance': "Today's Attendance",
      'punch_in': 'Punch In',
      'punch_out': 'Punch Out',
      'punched_in_at': 'Punched In',
      'punched_out_at': 'Punched Out',
      'work_hours': 'Work Duration',
      'geofence_status': 'Geofence Location',
      'inside_geofence': 'Inside Geofence Zone',
      'outside_geofence': 'Outside Geofence Zone',
      'quick_actions': 'Quick Actions',
      'recent_activity': 'Recent Activity',
      'no_records': 'No records found',
      'present': 'Present',
      'absent': 'Absent',
      'late': 'Late',
      'half_day': 'Half Day',
      'on_leave': 'On Leave',
      'pending': 'Pending',
      'approved': 'Approved',
      'rejected': 'Rejected',

      // Mark & Verify Attendance
      'align_face': 'Align face inside frame',
      'capturing_face': 'Capturing & verifying face...',
      'verifying_location': 'Checking GPS Geofence location...',
      'attendance_success_msg': 'Attendance marked successfully!',
      'attendance_fail_msg': 'Verification failed. Please try again.',
      'retry': 'Retry',

      // Admin Management
      'employee_management': 'Employee Management',
      'register_employee': 'Register Employee',
      'shift_management': 'Shift Management',
      'assign_shift': 'Assign Shift',
      'geofence_config': 'Geofence Configuration',
      'face_enrollment': 'Face Enrollment',
      'attendance_requests': 'Attendance Requests',
      'attendance_reports': 'Attendance Reports',
      'global_settings': 'Global Settings',
      'total_employees': 'Total Employees',
      'present_today': 'Present Today',
      'absent_today': 'Absent Today',
      'pending_requests': 'Pending Requests',
      'approve': 'Approve',
      'reject': 'Reject',
      'remarks': 'Remarks / Reason',
    },
    'mr': {
      // General & Auth
      'app_title': 'फील्डस्टाफ AI',
      'app_subtitle': 'बायोमेट्रिक व जिओफेन्स हजेरी प्रणाली',
      'sign_in': 'साइन इन करा',
      'login': 'लॉगिन',
      'employee_id': 'कर्मचारी आयडी / ॲडमिन आयडी',
      'password': 'पासवर्ड',
      'current_password': 'सध्याचा पासवर्ड',
      'new_password': 'नवीन पासवर्ड',
      'confirm_password': 'नवीन पासवर्डची पुष्टी करा',
      'please_enter_emp_id': 'कृपया कर्मचारी आयडी टाका',
      'please_enter_password': 'कृपया पासवर्ड टाका',
      'welcome': 'स्वागत आहे',
      'welcome_back': 'पुन्हा स्वागत आहे',
      'logout': 'लॉगआउट',
      'logout_confirm': 'तुम्हाला नक्की लॉगआउट करायचे आहे का?',
      'cancel': 'रद्द करा',
      'save': 'साठवा',
      'submit': 'सबमिट करा',
      'success': 'यशस्वी',
      'error': 'त्रुटी',
      'warning': 'सूचना',
      'refresh': 'रिफ्रेश करा',
      'search': 'शोधा',
      'filter': 'फिल्टर',
      'status': 'स्थिती',
      'date': 'दिनांक',
      'time': 'वेळ',
      'location': 'स्थान',
      'language': 'भाषा',
      'select_language': 'भाषा निवडा',
      'english': 'English',
      'marathi': 'मराठी',

      // Navigation & Titles
      'user_dashboard': 'कर्मचारी डॅशबोर्ड',
      'admin_dashboard': 'ॲडमिन डॅशबोर्ड',
      'mark_attendance': 'हजेरी नोंदवा',
      'verify_attendance': 'बायोमेट्रिक पडताळणी',
      'attendance_history': 'हजेरी इतिहास',
      'send_request': 'हजेरी दुरुस्ती विनंती',
      'request_history': 'विनंती स्थिती',
      'change_password': 'पासवर्ड बदला',
      'attendance_portal': 'हजेरी पोर्टल',

      // Greetings & Shifts
      'good_morning': 'शुभ सकाळ',
      'good_afternoon': 'शुभ दुपार',
      'good_evening': 'शुभ संध्याकाळ',
      'general_shift': 'जनरल शिफ्ट',
      'flexible_shift': 'लवचिक शिफ्ट (Flexible Shift)',
      'regular_shift_hours': 'नियमित शिफ्ट वेळ',

      // Shift & Location Cards
      'todays_shift': 'आजची शिफ्ट',
      'assigned': 'नेमून दिलेली',
      'work_location': 'कामाचे स्थान',
      'verified': 'पडताळलेले',
      'assigned_work_site': 'नेमून दिलेले कार्यस्थळ',

      // Main Button & Statuses
      'mark_attendance_btn': 'हजेरी नोंदवा',
      'attendance_recorded_btn': 'हजेरी नोंदवली गेली ✓',
      'service_unavailable': 'हजेरी सेवा सध्या उपलब्ध नाही.',
      'window_open_sub': 'हजेरी विंडो आता उघडी आहे.',
      'already_recorded_sub': 'हजेरी आधीच नोंदवली गेली आहे.',
      'window_closed_sub': 'हजेरीची मुदत संपली आहे.',
      'not_started_sub': 'हजेरी अजून सुरू झालेली नाही.',

      // Notifications / Countdown & Empty States
      'no_shift_assigned': 'कोणतीही शिफ्ट नेमलेली नाही',
      'no_shift_assigned_sub': 'आपण सध्या कोणत्याही सक्रिय शिफ्टला नेमलेले नाही.',
      'no_punch_schedule': 'आज कोणतेही वेळापत्रक नाही',
      'no_punch_schedule_sub': 'आज आपल्या शिफ्टसाठी हजेरीची वेळ शेड्यूल केलेली नाही.',
      'server_unavailable_title': 'हजेरी सेवा अनुपलब्ध आहे',
      'server_unavailable_sub': 'हजेरी सेवा सध्या उपलब्ध नाही. कृपया नंतर प्रयत्न करा.',
      'starts_in_min': '🔔 हजेरी {min} मिनिटांत सुरू होईल',
      'starts_in_less_min': '🔔 हजेरी १ मिनिटापेक्षा कमी वेळेत सुरू होईल',
      'get_ready': 'आपली हजेरी नोंदवण्यासाठी तयार रहा.',
      'window_open_title': '🟢 हजेरी विंडो आता उघडी आहे',
      'mark_now': 'कृपया आपली हजेरी नोंदवा.',
      'all_recorded_title': '✓ हजेरी आधीच नोंदवली गेली आहे',
      'all_recorded_sub': 'आपण आजची हजेरी यशस्वीरित्या पूर्ण केली आहे.',
      'window_closed_title': 'हजेरीची मुदत संपली आहे',
      'window_closed_desc': 'या शिफ्टसाठी हजेरीची मुदत संपली आहे.',

      // Schedule Card
      'todays_schedule': 'आजचे वेळापत्रक',
      'periods_count': '{count} टप्पे',
      'open_now': 'आता उघडे',
      'closed': 'बंद',
      'upcoming': 'येणारे',
      'completed': 'नोंदवले गेले ✓',

      // Requests & Issues
      'facing_issues': 'काही अडचण आहे का? हजेरी दुरुस्ती विनंती पाठवा',

      // Dashboard Elements
      'current_shift': 'सध्याची शिफ्ट',
      'today_attendance': 'आजची हजेरी',
      'punch_in': 'पंच इन',
      'punch_out': 'पंच आउट',
      'punched_in_at': 'पंच इन वेळ',
      'punched_out_at': 'पंच आउट वेळ',
      'work_hours': 'कामाचा कालावधी',
      'geofence_status': 'जिओफेन्स स्थान',
      'inside_geofence': 'जिओफेन्स क्षेत्रात उपलब्ध',
      'outside_geofence': 'जिओफेन्स क्षेत्राबाहेर',
      'quick_actions': 'जलद कृती',
      'recent_activity': 'अलिकडील नोंदी',
      'no_records': 'कोणतीही नोंद आढळली नाही',
      'present': 'उपस्थित',
      'absent': 'अनुपस्थित',
      'late': 'उशीरा',
      'half_day': 'अर्धा दिवस',
      'on_leave': 'रजेवर',
      'pending': 'प्रलंबित',
      'approved': 'मंजूर',
      'rejected': 'नाकारले',

      // Mark & Verify Attendance
      'align_face': 'चेहरा चौकटीत ठेवा',
      'capturing_face': 'चेहरा फोटो व पडताळणी सुरू आहे...',
      'verifying_location': 'GPS जिओफेन्स स्थान तपासत आहे...',
      'attendance_success_msg': 'हजेरी यशस्वीरित्या नोंदवली गेली!',
      'attendance_fail_msg': 'पडताळणी अपयशी ठरली. कृपया पुन्हा प्रयत्न करा.',
      'retry': 'पुन्हा प्रयत्न करा',

      // Admin Management
      'employee_management': 'कर्मचारी व्यवस्थापन',
      'register_employee': 'नवीन कर्मचारी नोंदणी',
      'shift_management': 'शिफ्ट व्यवस्थापन',
      'assign_shift': 'शिफ्ट असाइन करा',
      'geofence_config': 'जिओफेन्स कॉन्फिगरेशन',
      'face_enrollment': 'चेहरा नोंदणी',
      'attendance_requests': 'हजेरी विनंत्या',
      'attendance_reports': 'हजेरी अहवाल',
      'global_settings': 'ग्लोबल सेटिंग्ज',
      'total_employees': 'एकूण कर्मचारी',
      'present_today': 'आज उपस्थित',
      'absent_today': 'आज अनुपस्थित',
      'pending_requests': 'प्रलंबित विनंत्या',
      'approve': 'मंजूर करा',
      'reject': 'नाकारा',
      'remarks': 'शेरा / कारण',
    }
  };

  static String tr(String key, {Map<String, String>? args}) {
    final lang = LanguageService.instance.currentLanguageCode;
    String text = _localizedValues[lang]?[key] ?? _localizedValues['en']?[key] ?? key;
    if (args != null) {
      args.forEach((k, v) {
        text = text.replaceAll('{$k}', v);
      });
    }
    return text;
  }
}
