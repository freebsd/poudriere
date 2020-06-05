Name:		cpdup
Version:	1.21
Release:	2%{?dist}
Summary:	Filesystem mirroring utility from DragonFly BSD

License:	BSD
URL:		https://github.com/DragonFlyBSD/cpdup

BuildRequires:	make, gcc, binutils
BuildRequires:	pkgconfig, libbsd-devel, openssl-devel
Requires:	libbsd, openssl

%description
The "cpdup" utility makes an exact mirror copy of the source in the
destination, creating and deleting files and directories as necessary.
"cpdup" does not cross mount points in either the source or the destination.
As a safety measure, "cpdup" refuses to replace a destination directory with
a file.

%prep
# empty

%build
make

%install
rm -rf $RPM_BUILD_ROOT
install -s -Dm 755 %{name} %{buildroot}%{_bindir}/%{name}
install -Dm 644 %{name}.1 %{buildroot}%{_mandir}/man1/%{name}.1
gzip -9 %{buildroot}%{_mandir}/man1/%{name}.1

%files
%{_bindir}/%{name}
%{_mandir}/man1/%{name}.1.gz
%doc README.md
%doc BACKUPS
%doc PORTING
%license LICENSE

%changelog
* Fri Apr 10 2020 Aaron LI <aly@aaronly.me> - 1.21-2
- Simplify this RPM spec
* Sat Apr 4 2020 Aaron LI <aly@aaronly.me> - 1.21-1
- Support microsecond timestamp precision
* Fri Oct 25 2019 Aaron LI <aly@aaronly.me> - 1.20-1
- Initial package for version 1.20
