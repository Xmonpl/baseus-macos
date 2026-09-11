# Baseus Menu

Lekka, natywna aplikacja w pasku menu macOS do **Baseus Bass BP1 Pro ANC**.
SwiftUI + AppKit + CoreBluetooth, bez WebView, Node.js, zewnętrznych bibliotek i telemetrii.
Protokół przeniesiono z [elaxptr/baseus-desktop](https://github.com/elaxptr/baseus-desktop)
na podstawie rewizji zapisanej w [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Uruchomienie

1. Otwórz `dist` i skopiuj **Baseus Menu.app** do `/Applications`.
2. Uruchom aplikację. Pojawi się ikona słuchawek w pasku menu, bez ikony w Docku.
3. Zezwól na Bluetooth. Otwórz etui i wyjmij słuchawki.
4. Kliknij ikonę aplikacji → **Szukaj słuchawek** → **Połącz**.
5. Aplikacja automatycznie łączy również audio i wybiera słuchawki jako wyjście dźwięku.
   Jeśli słuchawki nie były nigdy sparowane z macOS, najpierw sparuj je w ustawieniach
   Bluetooth. Samo BLE nie tworzy parowania audio. Panel podpowie ten krok.

Od wersji 1.1 status **sterowania BLE** i **audio** jest pokazywany osobno.
Audio używa `IOBluetooth` do połączenia ze sparowanym urządzeniem i `CoreAudio`
do sprawdzenia/wyboru rzeczywistego wyjścia. Brak profilu audio nie jest traktowany
jako sukces. Próba trwa najwyżej 25 sekund, po czym można użyć „Połącz audio”.
Przy kilku sparowanych BP1 Pro aplikacja prosi o wskazanie urządzenia audio i
zapamiętuje powiązanie. Nie zgaduje, że identyfikator BLE jest adresem klasycznego Bluetooth.
W ustawieniach można wyłączyć „Łącz audio i wybieraj jako wyjście”. Późniejszy ręczny
wybór innego wyjścia jest respektowany; aplikacja nie przełącza dźwięku z powrotem
po zakończeniu próby. „Rozłącz sterowanie” i zamknięcie aplikacji nie przerywają audio.

Wymagany macOS 13 Ventura lub nowszy. Domyślny build odpowiada architekturze komputera;
`--universal` tworzy aplikację dla Apple Silicon i Intel.

Pakiet lokalny jest podpisany ad hoc. Nie jest notaryzowany przez Apple.
Przy dystrybucji na inne komputery potrzebny jest podpis Developer ID i notaryzacja.
Jeśli macOS blokuje pobraną kopię, użyj „Otwórz mimo to” w Prywatność i ochrona
wyłącznie dla znanego Ci pakietu; nie wyłączaj Gatekeepera globalnie.

## Funkcje

- Baterie lewej i prawej słuchawki oraz etui; ładowanie etui, procent w pasku menu.
- Zapytanie o baterie słuchawek co 60 sekund (z tolerancją 10 s), przycisk ponowienia
  i osobny czas ostatniego raportu dla słuchawek i etui. Podczas poleceń sterowania
  oraz szukania słuchawki automatyczne zapytanie jest pomijane.
- ANC, wyłączenie redukcji i tryb transparentny „Kontakt”; siła ANC.
- EQ: zrównoważony, więcej basu, głos.
- Niezależny tryb gry o niższym opóźnieniu.
- Znajdowanie lewej/prawej słuchawki: sygnał i automatyczne polecenie stop po 5 s.
- Zapamiętanie wybranego urządzenia; ponowne łączenie z odstępem 5–60 s.
- Automatyczne połączenie klasycznego Bluetooth audio i wybór wyjścia dźwięku.
- Obsługa uśpienia, wybudzenia, wyłączenia Bluetooth i utraty połączenia.
- Opcjonalne powiadomienia poniżej 20%, z histerezą i bez powtarzania każdego odczytu.
- Autostart przez natywne `SMAppService` (włączaj po przeniesieniu do Applications).
- Dla lokalnej kopii odrzuconej przez `SMAppService` błędem 22: zgodny z macOS wpis
  użytkownika w `~/Library/LaunchAgents/pl.xmon.BaseusMenu.login.plist`, bez procesu
  działającego stale w tle. Wyłączenie autostartu usuwa ten wpis. Działa od następnego
  logowania; przeniesienie aplikacji wymaga jej jednokrotnego ręcznego uruchomienia,
  aby zaktualizować zapisaną ścieżkę. Błędy uprawnień nie uruchamiają tego mechanizmu.
- Polski interfejs, jasny i ciemny wygląd, etykiety VoiceOver.
- Lokalny eksport ostatnich 200 wpisów diagnostycznych do wybranego pliku.
- Ostatnie 200 zdarzeń bieżącej sesji także w `~/Library/Logs/BaseusMenu/session.log`
  (odczyt i zapis tylko dla użytkownika). Plik jest zastępowany przy nowym uruchomieniu.

## Zasady odczytu i ograniczenia protokołu

Obsługiwany model to **Bass BP1 Pro ANC**. Sama nazwa Baseus nie oznacza zgodności.
Po wyborze urządzenia aplikacja sprawdza właściwą usługę i charakterystyki GATT.
Nie używa nieaktualnych UUID `02F0…` z ogólnej dokumentacji źródłowej ani
Windowsowego transportu. Nie implementuje aktualizacji firmware, gestów ani RFCOMM.

Nieodczytane wartości są oznaczone `—` lub „stan nieznany”. Aplikacja pyta o EQ,
natomiast początkowego ANC i trybu gry nie zgaduje — protokół źródłowy nie podaje
potwierdzonych poleceń ich odczytu. Wybór trybu ustawia go w słuchawkach.
Zmiana stanu pojawia się po odpowiedzi urządzenia, nie po samym kliknięciu.
Siła ANC po potwierdzeniu polecenia reprezentuje wysłaną wartość, ponieważ płaski
ACK firmware nie odsyła zmierzonej siły. Suwak skaluje zakres bajtów 16–255 do 0–100%.

Ramka `AA 30` jest keepalive, a `AA 24 01` potwierdzeniem odbioru bez stanu gry.
Płaskie `AA 34 01` potwierdza oczekujące polecenie ANC, także wyłączenie.
Nie jest interpretowane jako „ANC włączone” bez kontekstu.
Od wersji 1.2 zdarzenie `AA 33 [mode] [level]` odczytuje tryb z pola `mode`,
a nie z samego opcode `33`. Gest słuchawki wysłał w lokalnej próbie `AA 33 02 FF`:
to tryb transparentny, który poprzednia wersja błędnie pokazywała jako ANC.
Wartości trybu to 0=wyłączone, 1=ANC, 2=transparentny; nieznane wartości są ignorowane.
Zapisy są serializowane; limit oczekiwania wynosi 5 s. Brak odpowiedzi zrywa sesję,
aby spóźnione potwierdzenie nie zostało przypisane do następnego polecenia.

0% słuchawki może oznaczać odłożenie do etui. Znaczniki L/R w ramce baterii **nie są
flagami ładowania**. Bateria etui pojawia się dopiero po jego powiadomieniu i może
pozostawać ostatnim odczytem z bieżącej sesji. Po rozłączeniu odczyty są czyszczone.

EQ „Wyrazisty” (0x03) jest ekstrapolacją projektu źródłowego i domyślnie jest ukryty;
można go włączyć w ustawieniach jako eksperymentalny.
Szukanie korzysta z komendy ze źródłowej implementacji. Sygnał należy uruchamiać
po wyjęciu słuchawek z uszu. Przy utracie połączenia polecenie stop może nie dotrzeć;
włóż słuchawkę do etui, jeśli nadal piszczy.

## Budowanie i testy

W wersji 1.2.1 odczyt słuchawek korzysta z `BA 02`, znalezionego w zrzucie kodu
oficjalnego Androida (`FindEarPhoneActivity`, plik `bytecode-dump.txt` projektu źródłowego).
Na fizycznym BP1 Pro potwierdzono odpowiedź `AA 02` bez ponownego łączenia.
Zapytanie nie odświeża automatycznie etui — etui ma własne raporty `AA 27`.
Brak odpowiedzi nie zeruje baterii ani nie zmienia daty ostatniego odczytu.
Opcjonalny argument uruchomienia `--refresh-battery-once` wykonuje jedno dodatkowe
zapytanie 3 sekundy po połączeniu, przydatne do diagnostyki.

Wymagane Xcode z toolchainem Swift 6 i aktywnymi Command Line Tools.

```sh
swift test
./scripts/build.sh
open "dist/Baseus Menu.app"

# Opcjonalny build obu architektur:
./scripts/build.sh --universal

# Podpis własnym certyfikatem:
SIGNING_IDENTITY='Developer ID Application: Twoja nazwa (TEAMID)' ./scripts/build.sh --universal
```

Nie uruchamiaj bezpośrednio `swift run` do testów Bluetooth: pakiet `.app` zawiera
wymagany opis uprawnień i tożsamość aplikacji. Edycja w Xcode: otwórz `Package.swift`.

`Sources/BaseusProtocol` zawiera czysty kodek i stan; `Sources/BaseusMenu` transport,
cykl życia i UI. Testy obejmują rzeczywiste ramki z projektu źródłowego, komendy,
różnice ACK firmware, błędne/truncated ramki, nieznane wartości i reset sesji.
Testy nie zastępują weryfikacji radiowej na fizycznych słuchawkach.
W tej sesji potwierdzono też wykrycie i połączenie z fizycznym BP1 Pro oraz odczyt
baterii. Dokładny zakres i pozostałe próby opisuje [VALIDATION.md](VALIDATION.md).

### Próba na słuchawkach

1. Sprawdź wykrywanie i pierwsze połączenie; porównaj baterie z aplikacją Baseus.
2. Przełącz wszystkie tryby ANC, siłę, trzy EQ oraz włącz/wyłącz tryb gry.
3. Po wyjęciu słuchawek z uszu sprawdź sygnał i zatrzymanie po 5 sekundach.
4. Zamknij etui, otwórz ponownie; sprawdź uśpienie/wybudzenie Maca i Bluetooth off/on.
5. Ręczne „Rozłącz” powinno wstrzymać automatyczne łączenie do ponownego wyszukiwania.
6. Przetestuj autostart po instalacji do Applications i ponownym zalogowaniu.

Gdy nie widać słuchawek, zamknij aplikację Baseus na telefonie, sprawdź uprawnienia
Bluetooth i ponów wyszukiwanie. Po ponownym parowaniu może pomóc „Zapomnij urządzenie”
w ustawieniach aplikacji. Diagnostyka zawiera surowe ramki, które mogą zawierać
identyfikatory urządzenia; przejrzyj plik przed publicznym udostępnieniem.

## Licencja

MIT, z zachowaniem informacji o autorach protokołu. Niezależny projekt,
niepowiązany z producentem Baseus.
