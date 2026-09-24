<?php

use PHPMailer\PHPMailer\Exception;
use PHPMailer\PHPMailer\PHPMailer;

$autoload = __DIR__ . '/../vendor/autoload.php';
if (!file_exists($autoload)) {
    throw new RuntimeException('Email service is not installed. Run composer install in the project root.');
}
require_once $autoload;

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
