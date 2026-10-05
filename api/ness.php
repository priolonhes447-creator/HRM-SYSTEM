<?php

function getNessReply(string $message): string {
    $question = strtolower(trim($message));
    $outsideScope = 'That question is outside the scope of the system developed by Nhes Anthony N. Priolo.';

    if (preg_match('/\b(who (made|built|developed)|developer|developed by|created by|nhes anthony)\b/', $question)) {
        return 'This HR system was developed by Nhes Anthony N. Priolo. You can find the system description in the About section.';
    }

    if (preg_match('/\b(ness|ai assistant|chat box)\b/', $question)) {
        return 'I’m Ness, the guide for this HR system developed by Nhes Anthony N. Priolo. I can explain the system’s modules, access, and recruitment, interview, onboarding, employee, certificate, and settings workflows. I do not answer questions outside this system’s scope.';
    }

    if (preg_match('/\b(dark mode|dark theme|light mode|theme|appearance)\b/', $question)) {
        return 'To change the dashboard appearance, open your Profile menu, choose Settings, then select Light or Dark under Appearance.';
    }

    if (preg_match('/\b(contract signed|signed contract|contract photo|signed contract picture)\b/', $question)) {
        return 'In New Hire Onboarding, find the employee’s Contract Signed task and upload a clear picture of the signed contract. The task is marked complete after the upload succeeds.';
    }

    if (preg_match('/\b(onboarding|checklist|check list|onboard|employee id|employee number)\b/', $question)) {
        return 'After an applicant passes the interview and is completed as a hire, the system creates an employee record and Employee ID. Open New Hire Onboarding, expand the employee’s checklist, and update each required task. A signed-contract picture can be uploaded from the Contract Signed task; a successful upload marks that task complete.';
    }

    if (preg_match('/\b(certificate|mark as received|already received|proceed to employee record|employee module|unhired employee|unhired module)\b/', $question)) {
        return 'These are Admin-only employee-category actions. In Employee Records Management, use Complete to move an employee to Employee, or Unhired to move them to Unhired after entering a reason. In Employee, View Certificate opens the downloadable Certificate of Employment; Mark as Received records that it was received. Proceed to Employee Record opens the linked employee record. The HR account cannot access these Admin-only Employee and Unhired modules.';
    }

    if (preg_match('/\b(interview|schedule|qualified|not qualified|no show|did not pass)\b/', $question)) {
        return 'In the Recruitment Pipeline, select Not Qualified and enter a reason to move an applicant to Applicants Marked as Not Qualified. For a qualified applicant, choose Proceed to Interview, then set the interview date, time, interviewer, and location in Schedule Interview. Confirming the schedule sends the interview details to the applicant’s email; the applicant then appears in Applicants Ready for Interview. Use Status and Update to record Did Not Pass the Interview or No Show. If the applicant passes, mark the interview Complete to continue to onboarding.';
    }

    if (preg_match('/\b(recruitment|applicant|application|applying|apply|pipeline|portal|new hire)\b/', $question)) {
        return 'Applicants submit their details through the HR Recruitment Portal. Their applications appear in the Recruitment Pipeline for review. New applicants stay in that pipeline until HR records a decision: Not Qualified with a reason, or Proceed to Interview. The applicant then moves through interview scheduling and, if successful, onboarding.';
    }

    if (preg_match('/\b(password|forgot|reset password|verification code|otp)\b/', $question)) {
        return 'On the sign-in page, choose Forgot Password and enter your registered email. Enter the six-digit verification code sent to that email, then set and confirm a new password. If needed, use Resend Code.';
    }

    if (preg_match('/\b(profile|account|sign in|sign-in|login|log in|role|permission|access)\b/', $question)) {
        return 'Sign in with your account to open the dashboard. HR can manage recruitment, interviews, and onboarding. Admin accounts also have access to the Employee and Unhired employee-category modules, certificate controls, and user-account management. The HR account does not have those Admin-only controls.';
    }

    if (preg_match('/\b(hrms|hr system|this system|the system|system workflow|workflow)\b/', $question)) {
        return 'The workflow starts with an application through the HR Recruitment Portal. HR reviews applicants in the Recruitment Pipeline, marks unqualified applicants with a reason, and advances qualified applicants to interview scheduling. Interview outcomes determine whether the applicant continues to onboarding. After hire completion, the employee receives an Employee ID, appears in Employee Records, and completes onboarding tasks, including the signed-contract upload. Admin additionally manages Employee/Unhired categories and certificate receipt. Dark Mode is available in Settings.';
    }

    return $outsideScope;
}
