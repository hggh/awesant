Summary: Awesant is a log shipper for logstash.
Name: awesant
Version: 0.6
Release: 1%{?dist}
License: distributable
Group: System Environment/Daemons
Distribution: RHEL and CentOS
URL: http://download.bloonix.de/

Packager: Jonny Schulz <js@bloonix.de>
Vendor: Bloonix

BuildArch: noarch
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-%(%{__id_u} -n)

Source0: http://download.bloonix.de/sources/%{name}-%{version}.tar.gz
Requires: perl
Requires: perl(Log::Handler)
Requires: perl(Params::Validate)
Requires: perl(IO::Socket)
Requires: perl(IO::Select)
Requires: perl(JSON)
Requires: perl(Sys::Hostname)
Requires: perl(Time::HiRes)
Requires: perl(Class::Accessor::Fast)
AutoReqProv: no

%define initdir %{_sysconfdir}/rc.d/init.d
%define confdir %{_sysconfdir}/awesant
%define logrdir %{_sysconfdir}/logrotate.d
%define logdir %{_var}/log/awesant
%define libdir %{_var}/lib/awesant
%define defaults %{_sysconfdir}/sysconfig

%description
Awesant is a log shipper for logstash.

%prep
%setup -q -n %{name}-%{version}

%build
%{__perl} Configure.PL --prefix /usr --initdir %{initdir} --without-perl
%{__make}
cd perl;
%{__perl} Build.PL --installdirs vendor --destdir %{buildroot}
./Build

%install
rm -rf %{buildroot}
%{__make} install DESTDIR=%{buildroot}
mkdir -p %{buildroot}%{libdir}
mkdir -p %{buildroot}%{logdir}
install -D -m 644 etc/defaults/awesant-agent %{buildroot}%{defaults}/awesant-agent
install -D -m 644 etc/logrotate.d/awesant %{buildroot}%{logrdir}/awesant

cd perl;
./Build pure_install
find %{buildroot} -name .packlist -exec %{__rm} {} \;

%post
true

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root)

%{initdir}/awesant-agent
%{_bindir}/awesant

%dir %attr(0750, root, root) %{libdir}
%dir %attr(0750, root, root) %{logdir}
%dir %attr(0750, root, root) %{confdir}
%config(noreplace) %attr(0640, root, root) %{confdir}/agent.conf
%config(noreplace) %attr(0640, root, root) %{logrdir}/awesant
%config(noreplace) %attr(0640, root, root) %{defaults}/awesant-agent

%dir %{perl_vendorlib}/Awesant/
%dir %{perl_vendorlib}/Awesant/Input
%dir %{perl_vendorlib}/Awesant/Output
%{perl_vendorlib}/Awesant/*.pm
%{perl_vendorlib}/Awesant/Input/*.pm
%{perl_vendorlib}/Awesant/Output/*.pm
%{_mandir}/man?/Awesant::*

%changelog
* Thu Dec 06 2012 Jonny Schulz <js@bloonix.net> - 0.6-1
- Added a disconnect message to Output/Socket.pm.
- Added some benchmarking options to Agent.pm.
- Fixed "cat pidfile" in the init script.
- Added the new parameter 'format' for incoming messages.
- Added a input for tcp sockets.
- Now process groups are created for inputs that have the parameter 'workers' configured.
* Sun Nov 15 2012 Jonny Schulz <js@bloonix.net> - 0.4-1
- Implemented a extended add_field feature.
* Sun Nov 11 2012 Jonny Schulz <js@bloonix.net> - 0.3-1
- Fixed timestamp formatting.
- Modified an confusing error message.
- Some code improvements in Output/Redis.pm.
* Sun Nov 11 2012 Jonny Schulz <js@bloonix.net> - 0.2-1
- Fixed "Can't call method is_debug" in Output/Screen.pm.
- Added the feature that multiple types can be set for outputs.
- Deleted awesant.conf - this file will be build by make.
* Thu Nov 08 2012 Jonny Schulz <js@bloonix.net> - 0.1-1
- Initial package.
