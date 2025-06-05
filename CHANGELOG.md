0.1.0 first implementation that gets the job done
0.1.1 Ruby GEMs links
0.1.2 Typo
0.1.3 OpenAI support
0.1.5 claude json answer improved
0.2.0 n2r Ruby helper
0.2.1 converted to class, added logging possibility
0.2.2 Added Errbit integration with n2rrbit and n2rscrum commands including request parameters analysis
0.2.3 small bug fix
0.2.4 syntax fixes and improvements
0.3.0 Major diff analysis enhancement:
  - Added --diff/-d flag for AI-powered git/hg diff analysis
  - Added --requirements/-r flag for requirements compliance checking
  - Enhanced LLM prompts with code context extraction (±5-10 lines around changes)
  - Added test coverage assessment in diff analysis
  - Improved error handling with helpful messages for invalid options
  - Better JSON parsing to handle mixed LLM responses
  - Code organization improvements and method extraction
  - Requirements evaluation with clear status indicators (✅ ⚠️ ❌ 🔍)
0.3.1 Bug fixes and Mercurial branch support:
  - Fixed JSON parsing error in natural language commands
  - Added --branch/-b flag for comparing against specific branches
  - Full Mercurial (hg) branch comparison support with auto-detection
  - Git branch comparison with auto-detection of main/master branches
  - Enhanced branch validation and error handling for both git and hg
  - Option validation to prevent invalid flag combinations