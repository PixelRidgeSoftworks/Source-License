# Contributing to Source License

Thank you for considering contributing to Source License! We appreciate your interest in helping improve this comprehensive software licensing management system.

## 🚀 Quick Start

1. **Fork** the repository
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/your-username/Source-License.git
   cd Source-License
   ```
3. **Create** a feature branch:
   ```bash
   git checkout -b feature/amazing-feature
   ```
4. **Set up** the development environment following our [setup instructions](README.md#installation)

## 📋 Development Setup

### Prerequisites
- Ruby 3.4.4 or higher
- Git
- Database (MySQL, PostgreSQL, or SQLite for development)

### Installation
1. Run the appropriate install script for your platform:
   - Windows: `.\install.ps1`
   - Linux/macOS: `./install.sh`

2. Configure your environment:
   - Update database and other configuration settings

3. Run the deployment script:
   - Windows: `.\deploy.ps1`
   - Linux/macOS: `./deploy.sh`

## 🎯 How to Contribute

### Reporting Issues
- Use our [GitHub Issues](https://github.com/PixelRidge-Softworks/Source-License/issues) to report bugs
- Check existing issues before creating a new one
- Provide detailed reproduction steps and system information
- Include logs and error messages when applicable

### Suggesting Features
- Open a [GitHub Discussion](https://github.com/PixelRidge-Softworks/Source-License/discussions) for feature requests
- Explain the use case and benefit of your proposed feature
- Be open to feedback and alternative solutions

### Code Contributions

#### Before You Start
- Check existing issues and pull requests to avoid duplicate work
- For major changes, discuss your ideas in a GitHub Discussion first
- Make sure your contribution aligns with the project's goals

#### Development Guidelines

**Code Style**
- Follow Ruby community conventions
- Use RuboCop for style enforcement:
  ```bash
  bundle exec rubocop
  bundle exec rubocop -A  # Auto-fix issues
  ```

**Testing**
(This may be ignored for now, but will be enforced in the future)
- Write tests for new features and bug fixes
- Ensure all existing tests pass:
  ```bash
  bundle exec ruby -Itest test/app_test.rb
  ```
- Maintain test coverage with SimpleCov

**Architecture**
- Follow the existing modular controller architecture
- Place models in `lib/models.rb`
- Use appropriate controllers in `lib/controllers/`
- Follow the established patterns for database operations

#### Pull Request Process

1. **Update** your feature branch with the latest main:
   ```bash
   git checkout main
   git pull upstream main
   git checkout your-feature-branch
   git rebase main
   ```

2. **Test** your changes thoroughly:
   - Run the test suite (not needed for now but will be in the future)
   - Test manually with different configurations
   - Verify code style compliance

3. **Commit** your changes with descriptive messages:
   ```bash
   git commit -m "Add amazing feature: brief description of what it does"
   ```

4. **Push** to your fork:
   ```bash
   git push origin feature/amazing-feature
   ```

5. **Open** a Pull Request with:
   - Clear title and description
   - Reference related issues
   - Describe what changed and why
   - Include any breaking changes
   - Add screenshots for UI changes

## 📁 Project Structure

```
Source-License/
├── app.rb                 # Main application entry point
├── lib/
│   ├── models.rb         # Database models
│   ├── controllers/      # Modular controller architecture
│   ├── helpers.rb        # Template helpers
│   └── ...              # Core application logic
├── views/                # ERB templates
├── test/                 # Test suite
└── config/              # Configuration files
```

## 🔍 Code Quality

We maintain high code quality standards:

- **RuboCop**: Enforces Ruby style guide
- **Tests**: Comprehensive test coverage (not needed for now but will be in the future)
- **Security**: Security-first approach with proper authentication
- **Documentation**: Clear, concise documentation

## 💡 Areas We Need Help

- **Documentation**: Improving user and developer documentation
- **Testing**: Expanding test coverage, especially edge cases
- **Internationalization**: Multi-language support
- **UI/UX**: Improving the admin interface and user experience
- **Performance**: Optimization and caching improvements
- **Security**: Security audits and improvements
- **Integration**: Additional payment gateways and services

## 🎨 UI/UX Contributions

For design and user experience improvements:
- Focus on responsive, accessible design
- Follow Bootstrap conventions (current framework)
- Test across different devices and browsers
- Consider both admin and customer-facing interfaces

## 📝 Documentation Contributions

- Update README.md for new features
- Add code comments for complex logic
- Create or update API documentation
- Write or improve setup guides

## 🐛 Bug Reports

When reporting bugs, please include:
- **Operating System**: Version and distribution
- **Ruby Version**: `ruby --version`
- **Database**: Type and version
- **Steps to Reproduce**: Clear, numbered steps
- **Expected Behavior**: What should happen
- **Actual Behavior**: What actually happens
- **Logs**: Relevant error messages or logs
- **Screenshots**: For UI-related issues

## 📞 Getting Help

- **GitHub Discussions**: For questions and general discussion
- **GitHub Issues**: For bug reports and feature requests
- **Project Wiki**: For detailed documentation (not yet created)
- **Code Review**: We provide constructive feedback on pull requests

## 🏷️ Release Process

Source License follows semantic versioning:
- **MAJOR**: Breaking changes
- **MINOR**: New features, backwards compatible
- **PATCH**: Bug fixes, backwards compatible

## 📄 License

By contributing to Source License, you agree that your contributions will be licensed under the GNU General Public License v2.0.

## 🙏 Recognition

Contributors are recognized in:
- GitHub contributor graphs
- Release notes for significant contributions
- Project documentation where appropriate

## ⚠️ Alpha Status Notice

**Important**: Source License is currently in Alpha. Expect:
- Breaking changes between versions
- Missing functionality and documentation
- Bugs and stability issues
- Frequent updates and changes

Your contributions help us move toward a stable release!

---

**Thank you for contributing to Source License!** 🎉

Together, we're building a comprehensive licensing solution for software vendors worldwide.