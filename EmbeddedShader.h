class EmbeddedShader {
	private:
		EmbeddedShader();
		void operator=(const EmbeddedShader &o) {}
		EmbeddedShader(const EmbeddedShader &o) {}
	public:
		unsigned char *bytes = nullptr;
		const unsigned int length = 6998;
		static EmbeddedShader *$() {
			static EmbeddedShader instance;
			return &instance;
		}
};
