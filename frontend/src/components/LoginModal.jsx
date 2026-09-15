//StellarRoute\frontend\src\components\LoginModal.jsx

import React, { useState } from 'react';
import { X, Mail, Check, AlertTriangle, Loader2 } from 'lucide-react';
import { stellarRouteAPI } from '../services/api'; // Reuse existing API service

const LoginModal = ({ onClose, onSuccess }) => {
    const [step, setStep] = useState('email'); // 'email' or 'otp'
    const [email, setEmail] = useState('');
    const [otp, setOtp] = useState('');
    const [error, setError] = useState(null);
    const [loading, setLoading] = useState(false);

    // --- Step 1: Request OTP ---
    const handleRequestOtp = async (e) => {
        e.preventDefault();
        setError(null);
        setLoading(true);

        try {
            const response = await stellarRouteAPI.requestOtp(email);
            if (response.status === 202) {
                setStep('otp');
            }
        } catch (err) {
            console.error(err);
            setError(err.response?.data?.detail || 'Failed to send OTP. Check email format or server status.');
        } finally {
            setLoading(false);
        }
    };

    // --- Step 2: Verify OTP ---
    const handleVerifyOtp = async (e) => {
        e.preventDefault();
        setError(null);
        setLoading(true);

        try {
            const response = await stellarRouteAPI.verifyOtp(email, otp);
            
            // On success, the FastAPI backend will set the session_id cookie.
            // We just need to notify the App.jsx that login succeeded.
            if (response.status === 200) {
                // Pass the user email (or display name) back
                onSuccess(response.data.user_email); 
            }
        } catch (err) {
            console.error(err);
            setError(err.response?.data?.detail || 'Invalid OTP or session expired.');
        } finally {
            setLoading(false);
        }
    };

    const renderContent = () => {
        if (step === 'email') {
            return (
                <form onSubmit={handleRequestOtp} className="space-y-4">
                    <h3 className="text-xl font-semibold">Step 1: Enter Email</h3>
                    <p className="text-sm text-gray-600">We will send a One-Time Password to your email.</p>
                    <div className="relative">
                        <Mail className="absolute left-3 top-1/2 transform -translate-y-1/2 w-5 h-5 text-gray-400" />
                        <input
                            type="email"
                            placeholder="user@example.com"
                            value={email}
                            onChange={(e) => setEmail(e.target.value)}
                            required
                            className="w-full pl-10 pr-3 py-2 border border-gray-300 rounded-lg focus:ring-blue-500 focus:border-blue-500"
                        />
                    </div>
                    <button
                        type="submit"
                        disabled={loading}
                        className="w-full py-2 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg disabled:opacity-50 transition-colors flex items-center justify-center"
                    >
                        {loading ? <Loader2 className="w-5 h-5 animate-spin mr-2" /> : 'Send OTP'}
                    </button>
                </form>
            );
        }

        if (step === 'otp') {
            return (
                <form onSubmit={handleVerifyOtp} className="space-y-4">
                    <h3 className="text-xl font-semibold">Step 2: Verify OTP</h3>
                    <p className="text-sm text-gray-600">Enter the 6-digit code sent to **{email}**.</p>
                    <div className="relative">
                        <Check className="absolute left-3 top-1/2 transform -translate-y-1/2 w-5 h-5 text-gray-400" />
                        <input
                            type="text"
                            placeholder="------"
                            value={otp}
                            onChange={(e) => setOtp(e.target.value)}
                            required
                            maxLength="6"
                            className="w-full pl-10 pr-3 py-2 border border-gray-300 rounded-lg text-center tracking-widest text-lg focus:ring-green-500 focus:border-green-500"
                        />
                    </div>
                    <button
                        type="submit"
                        disabled={loading || otp.length < 6}
                        className="w-full py-2 bg-green-600 hover:bg-green-700 text-white font-medium rounded-lg disabled:opacity-50 transition-colors flex items-center justify-center"
                    >
                        {loading ? <Loader2 className="w-5 h-5 animate-spin mr-2" /> : 'Verify & Login'}
                    </button>
                    <button
                        type="button"
                        onClick={() => setStep('email')}
                        className="w-full py-1 text-sm text-gray-500 hover:text-gray-700"
                    >
                        &larr; Back to Email
                    </button>
                </form>
            );
        }
    };

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-[1000]">
            <div className="bg-white rounded-xl shadow-2xl p-6 w-full max-w-md relative">
                <button 
                    onClick={onClose} 
                    className="absolute top-4 right-4 text-gray-400 hover:text-gray-600"
                    aria-label="Close"
                >
                    <X className="w-6 h-6" />
                </button>
                <h2 className="text-2xl font-bold mb-6 text-gray-800 border-b pb-2">Login Challenge</h2>
                
                {error && (
                    <div className="mb-4 p-3 bg-red-100 border border-red-400 text-red-700 rounded-lg flex items-center">
                        <AlertTriangle className="w-5 h-5 mr-2 flex-shrink-0" />
                        <span className="text-sm">{error}</span>
                    </div>
                )}

                {renderContent()}
            </div>
        </div>
    );
};

export default LoginModal;