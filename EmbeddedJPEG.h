class EmbeddedJPEG {
	private:
		EmbeddedJPEG();
		void operator=(const EmbeddedJPEG &o) {}
		EmbeddedJPEG(const EmbeddedJPEG &o) {}
	public:
		unsigned char *bytes = nullptr;
		const unsigned int length = 103311;
		static EmbeddedJPEG *$() {
			static EmbeddedJPEG instance;
			return &instance;
		}
};
