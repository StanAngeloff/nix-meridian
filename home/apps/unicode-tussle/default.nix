{ lib, pkgs, ... }:
with pkgs;
with pkgs.perlPackages;
{
  # See https://nixos.wiki/wiki/Perl#Adding_something_from_CPAN_to_nixpkgs
  # See https://ryantm.github.io/nixpkgs/languages-frameworks/perl/#ssec-perl-packaging
  home.packages =
    let
      LinguaENSyllable = buildPerlPackage rec {
        pname = "Lingua-EN-Syllable";
        version = "0.31";
        src = fetchurl {
          url = "mirror://cpan/authors/id/N/NE/NEILB/${pname}-${version}.tar.gz";
          hash = "sha256-F5gd641ITRwb3qi/ampUEwOxkAk8BrQbKp1Rdlx3BM0=";
        };
        meta = {
          homepage = "https://github.com/neilb/Lingua-EN-Syllable";
          description = "Count the number of syllables in English words";
          license = with lib.licenses; [
            artistic1
            gpl1Plus
          ];
        };
      };
      LinguaKOHangulUtil = buildPerlPackage rec {
        pname = "Lingua-KO-Hangul-Util";
        version = "0.28";
        src = fetchurl {
          url = "mirror://cpan/authors/id/S/SA/SADAHIRO/${pname}-${version}.tar.gz";
          hash = "sha256-I/GGaYr/oaAZfjqGFa86te7WoNVb82kUpSR5uiJkKik=";
        };
        meta = {
          description = "Utility functions for Hangul in Unicode";
          license = with lib.licenses; [
            artistic1
            gpl1Plus
          ];
        };
      };
      LinguaKORomanizeHangul = buildPerlPackage rec {
        pname = "Lingua-KO-Romanize-Hangul";
        version = "0.20";
        src = fetchurl {
          url = "mirror://cpan/authors/id/K/KA/KAWASAKI/${pname}-${version}.tar.gz";
          hash = "sha256-vLpnO+KK2LgweB5chxjRr8Z5MTXKTGSWYQMflUM8Xaw=";
        };
        meta = {
          license = with lib.licenses; [
            artistic1
            gpl1Plus
          ];
        };
      };
      LinguaZHRomanizePinyin = buildPerlPackage rec {
        pname = "Lingua-ZH-Romanize-Pinyin";
        version = "0.23";
        src = fetchurl {
          url = "mirror://cpan/authors/id/K/KA/KAWASAKI/${pname}-${version}.tar.gz";
          hash = "sha256-oIiNAO4vNT7dVzWQTWpls0vBWBFXX9SW+640WHkTQJk=";
        };
        meta = {
        };
      };
      UnicodeLineBreak = buildPerlPackage rec {
        pname = "Unicode-LineBreak";
        version = "2019.001";
        src = fetchurl {
          url = "mirror://cpan/authors/id/N/NE/NEZUMI/${pname}-${version}.tar.gz";
          hash = "sha256-SGdi5MrN3Md7E5ifl5oCn4RjC4F15/7xeYnhV9S2MYo=";
        };
        propagatedBuildInputs = [ MIMECharset ];
        meta = {
          description = "UAX #14 Unicode Line Breaking Algorithm";
          license = with lib.licenses; [
            artistic1
            gpl1Plus
          ];
        };
      };
      UnicodeUnihan = buildPerlPackage rec {
        pname = "Unicode-Unihan";
        version = "0.045";
        src = fetchurl {
          url = "mirror://cpan/authors/id/B/BR/BRIANDFOY/${pname}-${version}.tar.gz";
          hash = "sha256-MzB6sXH1/BGq5TpQ0hknweSyGLJPdW/p0HYijx9/dL4=";
        };
        meta = {
          homepage = "https://github.com/briandfoy/unicode-unihan";
          description = "The Unihan Data Base 5.1.0";
          license = with lib.licenses; [
            artistic1
            gpl1Plus
          ];
        };
      };
      UnicodeTussle = buildPerlPackage rec {
        pname = "Unicode-Tussle";
        version = "1.121";
        src = fetchurl {
          url = "mirror://cpan/authors/id/B/BR/BRIANDFOY/${pname}-${version}.tar.gz";
          hash = "sha256-0/jIv6YewUaQ6AHrYppGtpPaflIU7+6IHaZYI5kplUQ=";
        };
        propagatedBuildInputs = [
          LinguaENSyllable
          LinguaKOHangulUtil
          LinguaKORomanizeHangul
          LinguaZHRomanizePinyin
          UnicodeLineBreak
          UnicodeUnihan
        ];
        meta = {
          homepage = "https://github.com/briandfoy/unicode-tussle";
          description = "Tom's Unicode Scripts So Life is Easier";
          license = with lib.licenses; [
            artistic1
            gpl1Plus
          ];
        };
        nativeBuildInputs = [ shortenPerlShebang ];
        postInstall = ''
          shortenPerlShebang $out/bin/uninames
        '';
      };
    in
    [
      UnicodeTussle
    ];
}
