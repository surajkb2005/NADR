abstract interface class AuthenticationRepository {
  Future<void> requestOtp({required String email});

  Future<bool> verifyOtp({required String email, required String otp});

  Future<bool> hasActiveSession();

  Future<void> signOut();
}
