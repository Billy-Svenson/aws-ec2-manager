# AWS EC2 Manager

A comprehensive bash script for managing AWS EC2 instances with an intuitive menu-driven interface.

## Features

- 🚀 **Launch EC2 Instances**: Create new instances with various AMIs and configurations
- 🛡️ **Security Group Management**: Create, modify, and manage security groups
- 📊 **Instance Information**: View detailed instance information and status
- 🌐 **Elastic IP Management**: Allocate, associate, and manage Elastic IPs
- ⚡ **Instance Actions**: Start, stop, reboot, and terminate instances
- 💾 **Storage Management**: View volumes and snapshots
- 🖼️ **AMI Management**: List and manage Amazon Machine Images
- 💰 **Cost Monitoring**: View cost information (requires root account)
- 🔑 **SSH Access**: Connect to instances via SSH with automatic key management

## Prerequisites

### Required Tools
- **AWS CLI**: Install and configure with your credentials
- **jq**: JSON processor for parsing AWS responses
- **curl**: For checking public IP addresses
- **netcat (nc)**: For port connectivity testing
- **ssh**: For connecting to instances

### Installation

#### Ubuntu/Debian
```bash
sudo apt update
sudo apt install awscli jq curl netcat-openbsd openssh-client
```

#### macOS
```bash
brew install awscli jq curl netcat openssh
```

#### CentOS/RHEL
```bash
sudo yum install awscli jq curl nc openssh-clients
```

### AWS Configuration

1. Install AWS CLI:
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

2. Configure AWS credentials:
```bash
aws configure
```

Enter your:
- AWS Access Key ID
- AWS Secret Access Key
- Default region (e.g., us-east-1)
- Default output format (json)

## Usage

### Quick Start

1. Clone or download the repository
2. Make scripts executable:
```bash
chmod +x *.sh
```

3. Run the main manager:
```bash
./manager.sh
```

### Scripts Overview

- **`manager.sh`**: Main menu-driven interface
- **`launch.sh`**: Standalone instance launcher
- **`utils.sh`**: Shared utility functions

### Key Features

#### Instance Launching
- Support for multiple AMIs (Amazon Linux, Ubuntu, RedHat, SUSE)
- Automatic key pair creation and management
- Security group creation with SSH access
- Instance type selection based on architecture
- Automatic username detection for SSH

#### Security
- Input validation and sanitization
- Proper SSH key permissions (600)
- Secure temporary file handling
- Error handling and cleanup

#### SSH Management
- Automatic SSH key management
- Ephemeral SSH sessions using EC2 Instance Connect
- Fallback to traditional SSH with key files
- Automatic security group rule updates

## Configuration

### Environment Variables

- `AWS_REGION`: Default AWS region (defaults to us-east-1)
- `AWS_PROFILE`: AWS profile to use (optional)

### CSV Storage

Instance metadata is stored in `~/.aws-manager-instances.csv` with the following format:
```
instance_id,instance_name,public_ip,key_path,username,security_group
```

## Security Considerations

1. **Key File Permissions**: All .pem files are automatically set to 600 permissions
2. **Input Validation**: All user inputs are validated and sanitized
3. **Temporary Files**: Temporary files are automatically cleaned up
4. **Error Handling**: Comprehensive error handling prevents script failures

## Troubleshooting

### Common Issues

1. **"aws: command not found"**
   - Install AWS CLI and ensure it's in your PATH

2. **"jq: command not found"**
   - Install jq using your package manager

3. **"Permission denied" on .pem files**
   - The script automatically sets correct permissions, but you can manually fix with:
   ```bash
   chmod 600 ~/.ssh/*.pem
   ```

4. **"No such file or directory: ./utils.sh"**
   - Ensure all script files are in the same directory

5. **SSH connection failures**
   - Check security group rules
   - Verify instance has public IP
   - Ensure key file exists and has correct permissions

### Debug Mode

Run with debug output:
```bash
bash -x ./manager.sh
```

## Supported AMIs

- Amazon Linux 2023
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS
- Red Hat Enterprise Linux 9
- SUSE Linux Enterprise Server 15

## Instance Types

The script automatically filters instance types based on the selected AMI architecture:
- **x86_64**: t2, t3, m5, c5 series
- **arm64**: t4g, m6g, c6g series

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is open source. See the LICENSE file for details.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review AWS CLI documentation
3. Open an issue on GitHub

## Changelog

### Version 2.0
- Complete rewrite with improved error handling
- Added comprehensive input validation
- Enhanced security features
- Better cross-platform compatibility
- Improved SSH management
- Added utility functions library

### Version 1.0
- Initial release
- Basic EC2 management functionality