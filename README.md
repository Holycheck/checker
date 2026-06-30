# Holy Checker

Holy Checker — Windows-утилита для быстрого скачивания набора программ по категориям.

Программа запускается как обычный `скрипт`. Пользователь запускает скрипт и может пользоваться без установки Visual Studio или дополнительных библиотек для самой программы.

## Возможности

- скачивание программ по вкладкам;
- скачивание всех программ сразу;
- многопоточная загрузка;
- автоматический переход на запасные ссылки;
- проверка скачанных файлов;
- распаковка `.zip` архивов в отдельные папки;
- отображение текущей скорости загрузки;
- итоговый список программ, которые не скачались.

## Вкладки

- Мл.сотрудник
- Сотрудник
- Вед.сотрудник

## Как использовать

1. Откройте Powershell от имени администратора
2. Вставьте команду iex (irm "https://raw.githubusercontent.com/Holycheck/checker/main/check.ps1")
3. Скрипт начнет проверку.
4. Дождитесь окончания.



## Требования для запуска

- Windows 10 или Windows 11.
- Подключение к интернету.

Для самой программы не требуется установка сторонних библиотек.

Некоторые скачиваемые сторонние утилиты могут требовать свои зависимости, например:

- .NET Desktop Runtime;
- Java Runtime.

Это относится к отдельным скачанным утилитам, а не к Holy Checker.

## Сборка проекта

### Требования для сборки

- Windows 10 или Windows 11;
- Visual Studio Build Tools;
- Windows SDK;
- MSVC C++ compiler.

### Сборка standalone EXE через MSVC

Откройте `Developer Command Prompt for VS` или терминал VS Code, где доступна команда `cl.exe`, и выполните:

```bat
cl /std:c++17 /EHsc /O2 /MT /DUNICODE /D_UNICODE main.cpp /Fe:HolyCheck.exe /link /SUBSYSTEM:WINDOWS user32.lib gdi32.lib comctl32.lib shell32.lib shlwapi.lib winhttp.lib wininet.lib ole32.lib oleaut32.lib uuid.lib dwmapi.lib gdiplus.lib advapi32.lib
```

После сборки появится файл:

```text
HolyCheck.exe
```

Ключ `/MT` используется для сборки максимально независимого `.exe` без необходимости отдельно устанавливать Microsoft Visual C++ Redistributable.

## Структура проекта

```text
main.cpp
parts/
README.md
.gitignore
POWERSHELL_COMMANDS.md
```

## Что не хранится в репозитории

В репозиторий не нужно добавлять:

- папку `build/`;
- `.exe` файлы;
- `.obj` файлы;
- `.pdb` файлы;
- временные архивы;
- `.part` файлы;
- файлы Visual Studio.
