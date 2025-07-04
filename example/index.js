import { AppRegistry } from 'react-native';

import { name as appName } from './app.json';
import App from './src/App';
import { setupAudioPro } from './src/player-service';

// Initialize the radio player
setupAudioPro();

AppRegistry.registerComponent(appName, () => App);
