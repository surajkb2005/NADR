//StellarRoute\frontend\src\components\EmailAuth.jsx

import React, { useState } from 'react';
import axios from 'axios'; // You'll need to install axios if not present

function EmailAuth() {
    // 1. STATE MANAGEMENT
    const [step, setStep] = useState(1); // 1: Email Input, 2: OTP Input
    const [email, setEmail] = useState('');
    const [otp, setOtp] = useState('');
    const [message, setMessage] = useState('');

    // --- HANDLER FUNCTIONS ---

    // 2. REQUEST OTP HANDLER (Step 1 Submit)
    const handleRequestOtp = async (e) => {
        e.preventDefault();
        setMessage('');
        try {
            // NOTE: Make sure your backend runs on a different port (e.g., 5000)
            const response = await axios.post(`${import.meta.env.VITE_API_URL}/api/auth/request-otp`, { email });
            
            // On success, move to the OTP input screen
            setMessage(response.data.message || "Code sent successfully!");
            setStep(2);

        } catch (error) {
            setMessage(error.response?.data?.message || 'Error sending code. Please try again.');
        }
    };

    // 3. VERIFY OTP HANDLER (Step 2 Submit)
    const handleVerifyOtp = async (e) => {
        e.preventDefault();
        setMessage('');
        try {
            
            await axios.post(`${import.meta.env.VITE_API_URL}/api/auth/request-otp`, { email, otp});
            
            // On successful verification, the backend sets the session cookie.
            // Redirect the user to the dashboard or protected area.
            alert('Login successful! Redirecting...'); 
            // In a real app: window.location.href = '/dashboard';

        } catch (error) {
            setMessage(error.response?.data?.message || 'Invalid or expired code.');
        }
    };

    // --- RENDERING ---

    return (
        <div className="auth-container">
            <h3>Brownie Login Challenge</h3>
            
            {/* Display status messages */}
            {message && <p className={message.startsWith('Error') ? 'text-red' : 'text-green'}>{message}</p>}

            {/* Step 1: Email Input Form */}
            {step === 1 && (
                <form onSubmit={handleRequestOtp}>
                    <input
                        type="email"
                        placeholder="Enter your email"
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                        required
                    />
                    <button type="submit">Send Login Code</button>
                </form>
            )}

            {/* Step 2: OTP Input Form */}
            {step === 2 && (
                <form onSubmit={handleVerifyOtp}>
                    <p>Enter the 6-digit code sent to <b>{email}</b></p>
                    <input
                        type="text"
                        placeholder="Enter 6-digit code"
                        value={otp}
                        onChange={(e) => setOtp(e.target.value)}
                        maxLength="6"
                        required
                    />
                    <button type="submit">Verify & Log In</button>
                    <button type="button" onClick={() => setStep(1)} className="mt-2">Back to Email</button>
                </form>
            )}
        </div>
    );
}

export default EmailAuth;