import 'package:google_fonts/google_fonts.dart';
import '../../editor/data/font.dart';

/// 전체 폰트 카탈로그 (100개 이상)
class FontCatalog {
  static final List<FontItem> all = [
    // ========== 기본 시스템 폰트 ==========
    FontItem(
      displayName: '기본 산세리프',
      category: '산세리프',
      localFontFamily: null,
      supportsKorean: true,
    ),

    // ========== 한글 손글씨체 (Google Fonts) ==========
    FontItem(
      displayName: '나눔손글씨 펜',
      category: '손글씨',
      googleFont: GoogleFonts.nanumPenScript,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Gaegu',
      category: '손글씨',
      googleFont: GoogleFonts.gaegu,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Poor Story',
      category: '손글씨',
      googleFont: GoogleFonts.poorStory,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Gamja Flower',
      category: '손글씨',
      googleFont: GoogleFonts.gamjaFlower,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Cute Font',
      category: '손글씨',
      googleFont: GoogleFonts.cuteFont,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Single Day',
      category: '손글씨',
      googleFont: GoogleFonts.singleDay,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Hi Melody',
      category: '손글씨',
      googleFont: GoogleFonts.hiMelody,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Yeon Sung',
      category: '손글씨',
      googleFont: GoogleFonts.yeonSung,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Dokdo',
      category: '손글씨',
      googleFont: GoogleFonts.dokdo,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Do Hyeon',
      category: '손글씨',
      googleFont: GoogleFonts.doHyeon,
      supportsKorean: true,
    ),

    // ========== 한글 산세리프 (Google Fonts) ==========
    FontItem(
      displayName: 'Noto Sans KR',
      category: '산세리프',
      googleFont: GoogleFonts.notoSansKr,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Nanum Gothic',
      category: '산세리프',
      googleFont: GoogleFonts.nanumGothic,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Nanum Gothic Coding',
      category: '산세리프',
      googleFont: GoogleFonts.nanumGothicCoding,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Black Han Sans',
      category: '산세리프',
      googleFont: GoogleFonts.blackHanSans,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Jua',
      category: '산세리프',
      googleFont: GoogleFonts.jua,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Sunflower',
      category: '산세리프',
      googleFont: GoogleFonts.sunflower,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Gothic A1',
      category: '산세리프',
      googleFont: GoogleFonts.gothicA1,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'IBM Plex Sans KR',
      category: '산세리프',
      googleFont: GoogleFonts.ibmPlexSansKr,
      supportsKorean: true,
    ),

    // ========== 한글 세리프 (Google Fonts) ==========
    FontItem(
      displayName: 'Noto Serif KR',
      category: '세리프',
      googleFont: GoogleFonts.notoSerifKr,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Nanum Myeongjo',
      category: '세리프',
      googleFont: GoogleFonts.nanumMyeongjo,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Gowun Batang',
      category: '세리프',
      googleFont: GoogleFonts.gowunBatang,
      supportsKorean: true,
    ),
    FontItem(
      displayName: 'Gowun Dodum',
      category: '세리프',
      googleFont: GoogleFonts.gowunDodum,
      supportsKorean: true,
    ),

    // ========== 영문 세리프 (인기 폰트) ==========
    FontItem(
      displayName: 'Playfair Display',
      category: '세리프',
      googleFont: GoogleFonts.playfairDisplay,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Merriweather',
      category: '세리프',
      googleFont: GoogleFonts.merriweather,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Lora',
      category: '세리프',
      googleFont: GoogleFonts.lora,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Crimson Text',
      category: '세리프',
      googleFont: GoogleFonts.crimsonText,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'EB Garamond',
      category: '세리프',
      googleFont: GoogleFonts.ebGaramond,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Cormorant',
      category: '세리프',
      googleFont: GoogleFonts.cormorant,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Libre Baskerville',
      category: '세리프',
      googleFont: GoogleFonts.libreBaskerville,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Source Serif 4',
      category: '세리프',
      googleFont: GoogleFonts.sourceSerif4,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Spectral',
      category: '세리프',
      googleFont: GoogleFonts.spectral,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Cardo',
      category: '세리프',
      googleFont: GoogleFonts.cardo,
      supportsKorean: false,
    ),

    // ========== 영문 산세리프 (인기 폰트) ==========
    FontItem(
      displayName: 'Inter',
      category: '산세리프',
      googleFont: GoogleFonts.inter,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Roboto',
      category: '산세리프',
      googleFont: GoogleFonts.roboto,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Open Sans',
      category: '산세리프',
      googleFont: GoogleFonts.openSans,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Lato',
      category: '산세리프',
      googleFont: GoogleFonts.lato,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Montserrat',
      category: '산세리프',
      googleFont: GoogleFonts.montserrat,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Poppins',
      category: '산세리프',
      googleFont: GoogleFonts.poppins,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Source Sans 3',
      category: '산세리프',
      googleFont: GoogleFonts.sourceSans3,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Raleway',
      category: '산세리프',
      googleFont: GoogleFonts.raleway,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'PT Sans',
      category: '산세리프',
      googleFont: GoogleFonts.ptSans,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Nunito',
      category: '산세리프',
      googleFont: GoogleFonts.nunito,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Work Sans',
      category: '산세리프',
      googleFont: GoogleFonts.workSans,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Rubik',
      category: '산세리프',
      googleFont: GoogleFonts.rubik,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'DM Sans',
      category: '산세리프',
      googleFont: GoogleFonts.dmSans,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Lexend',
      category: '산세리프',
      googleFont: GoogleFonts.lexend,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Josefin Sans',
      category: '산세리프',
      googleFont: GoogleFonts.josefinSans,
      supportsKorean: false,
    ),

    // ========== 디스플레이/장식 폰트 ==========
    FontItem(
      displayName: 'Bebas Neue',
      category: '디스플레이',
      googleFont: GoogleFonts.bebasNeue,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Righteous',
      category: '디스플레이',
      googleFont: GoogleFonts.righteous,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Fredoka',
      category: '디스플레이',
      googleFont: GoogleFonts.fredoka,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Comfortaa',
      category: '디스플레이',
      googleFont: GoogleFonts.comfortaa,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Pacifico',
      category: '디스플레이',
      googleFont: GoogleFonts.pacifico,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Lobster',
      category: '디스플레이',
      googleFont: GoogleFonts.lobster,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Dancing Script',
      category: '디스플레이',
      googleFont: GoogleFonts.dancingScript,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Sacramento',
      category: '디스플레이',
      googleFont: GoogleFonts.sacramento,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Great Vibes',
      category: '디스플레이',
      googleFont: GoogleFonts.greatVibes,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Satisfy',
      category: '디스플레이',
      googleFont: GoogleFonts.satisfy,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Abril Fatface',
      category: '디스플레이',
      googleFont: GoogleFonts.abrilFatface,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Anton',
      category: '디스플레이',
      googleFont: GoogleFonts.anton,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Bangers',
      category: '디스플레이',
      googleFont: GoogleFonts.bangers,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Press Start 2P',
      category: '디스플레이',
      googleFont: GoogleFonts.pressStart2p,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Alfa Slab One',
      category: '디스플레이',
      googleFont: GoogleFonts.alfaSlabOne,
      supportsKorean: false,
    ),

    // ========== 모노스페이스 (코딩 폰트) ==========
    FontItem(
      displayName: 'JetBrains Mono',
      category: '모노스페이스',
      googleFont: GoogleFonts.jetBrainsMono,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Fira Code',
      category: '모노스페이스',
      googleFont: GoogleFonts.firaCode,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Source Code Pro',
      category: '모노스페이스',
      googleFont: GoogleFonts.sourceCodePro,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'IBM Plex Mono',
      category: '모노스페이스',
      googleFont: GoogleFonts.ibmPlexMono,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Roboto Mono',
      category: '모노스페이스',
      googleFont: GoogleFonts.robotoMono,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Space Mono',
      category: '모노스페이스',
      googleFont: GoogleFonts.spaceMono,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Courier Prime',
      category: '모노스페이스',
      googleFont: GoogleFonts.courierPrime,
      supportsKorean: false,
    ),

    // ========== 추가 영문 세리프 ==========
    FontItem(
      displayName: 'Vollkorn',
      category: '세리프',
      googleFont: GoogleFonts.vollkorn,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Bitter',
      category: '세리프',
      googleFont: GoogleFonts.bitter,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Alegreya',
      category: '세리프',
      googleFont: GoogleFonts.alegreya,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Arvo',
      category: '세리프',
      googleFont: GoogleFonts.arvo,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Rokkitt',
      category: '세리프',
      googleFont: GoogleFonts.rokkitt,
      supportsKorean: false,
    ),

    // ========== 추가 영문 산세리프 ==========
    FontItem(
      displayName: 'Manrope',
      category: '산세리프',
      googleFont: GoogleFonts.manrope,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Quicksand',
      category: '산세리프',
      googleFont: GoogleFonts.quicksand,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Barlow',
      category: '산세리프',
      googleFont: GoogleFonts.barlow,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Outfit',
      category: '산세리프',
      googleFont: GoogleFonts.outfit,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Titillium Web',
      category: '산세리프',
      googleFont: GoogleFonts.titilliumWeb,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Karla',
      category: '산세리프',
      googleFont: GoogleFonts.karla,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Oxygen',
      category: '산세리프',
      googleFont: GoogleFonts.oxygen,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Maven Pro',
      category: '산세리프',
      googleFont: GoogleFonts.mavenPro,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Hind',
      category: '산세리프',
      googleFont: GoogleFonts.hind,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Varela Round',
      category: '산세리프',
      googleFont: GoogleFonts.varelaRound,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Noto Sans',
      category: '산세리프',
      googleFont: GoogleFonts.notoSans,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Ubuntu',
      category: '산세리프',
      googleFont: GoogleFonts.ubuntu,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Asap',
      category: '산세리프',
      googleFont: GoogleFonts.asap,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Exo 2',
      category: '산세리프',
      googleFont: GoogleFonts.exo2,
      supportsKorean: false,
    ),

    // ========== 추가 디스플레이 폰트 ==========
    FontItem(
      displayName: 'Yellowtail',
      category: '디스플레이',
      googleFont: GoogleFonts.yellowtail,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Cookie',
      category: '디스플레이',
      googleFont: GoogleFonts.cookie,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Kaushan Script',
      category: '디스플레이',
      googleFont: GoogleFonts.kaushanScript,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Indie Flower',
      category: '디스플레이',
      googleFont: GoogleFonts.indieFlower,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Shadows Into Light',
      category: '디스플레이',
      googleFont: GoogleFonts.shadowsIntoLight,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Permanent Marker',
      category: '디스플레이',
      googleFont: GoogleFonts.permanentMarker,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Amatic SC',
      category: '디스플레이',
      googleFont: GoogleFonts.amaticSc,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Caveat',
      category: '디스플레이',
      googleFont: GoogleFonts.caveat,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Zeyada',
      category: '디스플레이',
      googleFont: GoogleFonts.zeyada,
      supportsKorean: false,
    ),
    FontItem(
      displayName: 'Allura',
      category: '디스플레이',
      googleFont: GoogleFonts.allura,
      supportsKorean: false,
    ),
  ];

  /// 카테고리별로 필터링
  static List<FontItem> getByCategory(String category) {
    return all.where((f) => f.category == category).toList();
  }

  /// 한글 지원 폰트만 필터링
  static List<FontItem> getKoreanSupported() {
    return all.where((f) => f.supportsKorean).toList();
  }

  /// identifier로 폰트 찾기
  static FontItem? findByIdentifier(String identifier) {
    try {
      return all.firstWhere((f) => f.identifier == identifier);
    } catch (_) {
      return null;
    }
  }
}
