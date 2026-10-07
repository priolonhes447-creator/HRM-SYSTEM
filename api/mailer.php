<?php

use PHPMailer\PHPMailer\Exception;
use PHPMailer\PHPMailer\PHPMailer;

$autoload = __DIR__ . '/../vendor/autoload.php';
if (!file_exists($autoload)) {
    throw new RuntimeException('Email service is not installed. Run composer install in the project root.');
}
require_once $autoload;

function sendAdminLoginVerificationEmail(string $recipient, string $otp): void {
    if (!MAIL_HOST || !MAIL_USERNAME || !MAIL_PASSWORD || !MAIL_FROM_ADDRESS) {
        throw new RuntimeException('SMTP email settings are incomplete.');
    }

    $mail = new PHPMailer(true);
    $mail->isSMTP();
    $mail->Host = MAIL_HOST;
    $mail->Port = MAIL_PORT;
    $mail->SMTPAuth = true;
    $mail->Username = MAIL_USERNAME;
    $mail->Password = MAIL_PASSWORD;
    $mail->SMTPSecure = MAIL_ENCRYPTION === 'ssl'
        ? PHPMailer::ENCRYPTION_SMTPS
        : PHPMailer::ENCRYPTION_STARTTLS;
    $mail->CharSet = 'UTF-8';
    $mail->setFrom(MAIL_FROM_ADDRESS, MAIL_FROM_NAME);
    $mail->addAddress($recipient);
    $mail->isHTML(true);
    $mail->Subject = 'HRMS Admin Login Verification Code';
    $mail->Body = '<p>A sign-in attempt for your HRMS Admin/HR account requires email verification.</p>'
        . '<p>Your six-digit verification code is:</p>'
        . '<p style="font-size:24px;font-weight:bold;letter-spacing:6px;">' . htmlspecialchars($otp, ENT_QUOTES, 'UTF-8') . '</p>'
        . '<p>This code expires in 5 minutes. If you did not attempt to sign in, you can ignore this email.</p>';
    $mail->AltBody = "Your HRMS login verification code is {$otp}. It expires in 5 minutes.";
    $mail->send();
}

function sendPasswordResetEmail(string $recipient, string $otp): void {
    if (!MAIL_HOST || !MAIL_USERNAME || !MAIL_PASSWORD || !MAIL_FROM_ADDRESS) {
        throw new RuntimeException('SMTP email settings are incomplete.');
    }

    $mail = new PHPMailer(true);
    $mail->isSMTP();
    $mail->Host = MAIL_HOST;
    $mail->Port = MAIL_PORT;
    $mail->SMTPAuth = true;
    $mail->Username = MAIL_USERNAME;
    $mail->Password = MAIL_PASSWORD;
    $mail->SMTPSecure = MAIL_ENCRYPTION === 'ssl'
        ? PHPMailer::ENCRYPTION_SMTPS
        : PHPMailer::ENCRYPTION_STARTTLS;
    $mail->CharSet = 'UTF-8';
    $mail->setFrom(MAIL_FROM_ADDRESS, MAIL_FROM_NAME);
    $mail->addAddress($recipient);
    $mail->isHTML(true);
    $mail->Subject = 'Password Reset Verification';
    $mail->Body = '<p>We received a request to reset your HRMS password.</p>'
        . '<p>Your verification code is:</p>'
        . '<p style="font-size:24px;font-weight:bold;letter-spacing:6px;">' . htmlspecialchars($otp, ENT_QUOTES, 'UTF-8') . '</p>'
        . '<p>This code will expire in 5 minutes.</p>'
        . '<p>If you did not request a password reset, you can ignore this email.</p>';
    $mail->AltBody = "Your HRMS password reset code is {$otp}. It expires in 5 minutes.";
    $mail->send();
}

function sendInterviewScheduledEmail(string $recipient, array $interview): void {
    if (!MAIL_HOST || !MAIL_USERNAME || !MAIL_PASSWORD || !MAIL_FROM_ADDRESS) {
        throw new RuntimeException('SMTP email settings are incomplete.');
    }

    $escape = static function ($value): string {
        return htmlspecialchars((string)$value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    };
    $details = [
        'Applicant' => $interview['applicant_name'],
        'Position' => $interview['position'] ?: 'Not specified',
        'Interview Date' => $interview['interview_date'],
        'Interview Time' => $interview['interview_time'],
        'Interviewer' => $interview['interviewer'],
        'Location' => $interview['location'] ?: 'To be confirmed',
        'Notes' => $interview['notes'] ?: 'None'
    ];
    $rows = '';
    $plainDetails = [];
    foreach ($details as $label => $value) {
        $rows .= '<tr><th style="padding:8px 12px;text-align:left;vertical-align:top;border-bottom:1px solid #e5e7eb;">'
            . $escape($label) . '</th><td style="padding:8px 12px;border-bottom:1px solid #e5e7eb;">'
            . nl2br($escape($value)) . '</td></tr>';
        $plainDetails[] = $label . ': ' . $value;
    }

    $mail = new PHPMailer(true);
    $mail->isSMTP();
    $mail->Host = MAIL_HOST;
    $mail->Port = MAIL_PORT;
    $mail->SMTPAuth = true;
    $mail->Username = MAIL_USERNAME;
    $mail->Password = MAIL_PASSWORD;
    $mail->SMTPSecure = MAIL_ENCRYPTION === 'ssl'
        ? PHPMailer::ENCRYPTION_SMTPS
        : PHPMailer::ENCRYPTION_STARTTLS;
    $mail->CharSet = 'UTF-8';
    $mail->setFrom(MAIL_FROM_ADDRESS, MAIL_FROM_NAME);
    $mail->addAddress($recipient);
    $mail->isHTML(true);
    $mail->Subject = 'Your interview has been scheduled';
    $mail->Body = '<p>Hello ' . $escape($interview['applicant_name']) . ',</p>'
        . '<p>Your interview has been scheduled. Here are the details:</p>'
        . '<table style="width:100%;max-width:640px;border-collapse:collapse;">' . $rows . '</table>'
        . '<p>Please contact the Recruitment Team if you have any questions.</p>';
    $mail->AltBody = "Hello {$interview['applicant_name']},\n\nYour interview has been scheduled.\n\n"
        . implode("\n", $plainDetails)
        . "\n\nPlease contact the Recruitment Team if you have any questions.";
    $mail->send();
}
