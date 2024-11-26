from flask import Flask, request, jsonify
import pandas as pd
import numpy as np
import traceback
import io
import base64
import logging
from sklearn.preprocessing import LabelEncoder
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestRegressor, RandomForestClassifier
from sklearn.linear_model import LogisticRegression, LinearRegression
from sklearn.neighbors import KNeighborsClassifier
from sklearn.naive_bayes import GaussianNB
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from xgboost import XGBRegressor, XGBClassifier
from sklearn.tree import DecisionTreeRegressor
from sklearn.metrics import (
    accuracy_score, mean_squared_error, mean_absolute_error,
    r2_score, confusion_matrix, classification_report
)
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import seaborn as sns
import time
from collections import Counter

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 100 * 1024 * 1024  # 16MB max file size

CLASSIFIER_REGISTRY = {
    'logistic_regression': LogisticRegression(max_iter=1000),
    'knn': KNeighborsClassifier(),
    'naive_bayes': GaussianNB(),
    'random_forest_classifier': RandomForestClassifier(n_estimators=100),
    'xgboost_classifier': XGBClassifier(use_label_encoder=False, eval_metric='mlogloss'),
    'lda_classifier': LinearDiscriminantAnalysis()
}

REGRESSOR_REGISTRY = {
    'linear_regression': LinearRegression(),
    'xgboost_regressor': XGBRegressor(),
    'decision_tree_regressor': DecisionTreeRegressor(),
    'random_forest_regressor': RandomForestRegressor(n_estimators=100)
}

@app.route('/train', methods=['POST'])
def train():
    try:
        logger.info("Starting training process")
        
        # Get selected models
        classifier_name = request.args.get('classifier', 'random_forest_classifier')
        regressor_name = request.args.get('regressor', 'random_forest_regressor')
        
        logger.info(f"Selected models - Classifier: {classifier_name}, Regressor: {regressor_name}")
        
        if classifier_name not in CLASSIFIER_REGISTRY:
            return jsonify({'error': f'Invalid classifier. Available: {list(CLASSIFIER_REGISTRY.keys())}'})
        if regressor_name not in REGRESSOR_REGISTRY:
            return jsonify({'error': f'Invalid regressor. Available: {list(REGRESSOR_REGISTRY.keys())}'})
        
        # Read data
        file = request.files.get('file')
        if not file:
            return jsonify({'error': 'No file provided'})
        
        df = pd.read_csv(file)
        logger.info(f"Data loaded with shape: {df.shape}")
        logger.debug(f"Columns in dataset: {df.columns.tolist()}")
        
        # Identify dynamic sensor columns
        sensor_columns = [col for col in df.columns if col.startswith('Sensor ')]
        num_sensors = len(sensor_columns)
        logger.info(f"Detected {num_sensors} sensors: {sensor_columns}")
        
        # Check required columns
        required_columns = ['Time'] + sensor_columns + ['Type', 'Concentration']
        missing_columns = [col for col in required_columns if col not in df.columns]
        if missing_columns:
            return jsonify({'error': f'Missing required columns: {missing_columns}'})
        
        # Split data
        train_df, _ = train_test_split(df, test_size=0.2, random_state=42)
        logger.info(f"Training data shape: {train_df.shape}")
        
        # Prepare features
        X_train = train_df[['Time'] + sensor_columns]
        logger.debug(f"Feature columns: {X_train.columns.tolist()}")
        logger.debug(f"Sample of X_train:\n{X_train.head()}")
        
        # Prepare targets
        le = LabelEncoder()
        y_class_train = le.fit_transform(train_df['Type'])
        y_reg_train = train_df['Concentration']
        
        logger.info(f"Unique gas types: {le.classes_.tolist()}")
        logger.info(f"Concentration range: [{y_reg_train.min()}, {y_reg_train.max()}]")
        
        # Train models
        classifier = CLASSIFIER_REGISTRY[classifier_name]
        regressor = REGRESSOR_REGISTRY[regressor_name]
        
        start_time = time.time()
        
        # Train classifier and regressor
        classifier.fit(X_train, y_class_train)
        regressor.fit(X_train, y_reg_train)
        
        training_time = time.time() - start_time
        logger.info(f"Training completed in {training_time:.2f} seconds")
        
        # Store models and metadata
        app.config['classifier'] = classifier
        app.config['regressor'] = regressor
        app.config['label_encoder'] = le
        app.config['num_sensors'] = num_sensors
        app.config['feature_columns'] = ['Time'] + sensor_columns
        
        return jsonify({
            'message': 'Models trained successfully',
            'training_time': training_time,
            'num_sensors': num_sensors,
            'feature_columns': ['Time'] + sensor_columns,
            'unique_gas_types': le.classes_.tolist()
        })
        
    except Exception as e:
        logger.error(f"Training error: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({'error': str(e)}), 500

@app.route('/predict', methods=['POST'])
def predict():
    try:
        logger.info("Starting prediction process")
        
        if 'classifier' not in app.config or 'regressor' not in app.config:
            return jsonify({'error': 'Models not trained. Please train models first.'})
        
        file = request.files.get('file')
        if not file:
            return jsonify({'error': 'No file provided'})
        
        df = pd.read_csv(file)
        logger.info(f"Prediction data loaded with shape: {df.shape}")
        logger.debug(f"Columns in prediction data: {df.columns.tolist()}")
        
        num_sensors = app.config['num_sensors']
        feature_columns = app.config['feature_columns']
        
        # Verify columns match training data
        missing_columns = [col for col in feature_columns if col not in df.columns]
        if missing_columns:
            return jsonify({'error': f'Missing required columns: {missing_columns}'})
        
        # Make predictions
        X = df[feature_columns]
        logger.debug(f"Prediction features shape: {X.shape}")
        logger.debug(f"Sample of prediction features:\n{X.head()}")
        
        y_class_pred = app.config['classifier'].predict(X)
        gas_types = app.config['label_encoder'].inverse_transform(y_class_pred)
        concentrations = app.config['regressor'].predict(X)
        
        logger.info(f"Predicted gas types: {set(gas_types.tolist())}")
        logger.info(f"Concentration range: [{concentrations.min()}, {concentrations.max()}]")
        
        # Calculate summary statistics
        mode_concentration = float(np.around(np.mean(concentrations), 2))
        mode_gas_type = max(set(gas_types.tolist()), key=gas_types.tolist().count)
        
        # Create detailed results
        results = {
            'predicted_gas_type': mode_gas_type,
            'predicted_concentration': mode_concentration,
            'predictions': {
                'gas_types': gas_types.tolist(),
                'concentrations': concentrations.tolist()
            },
            'summary': {
                'unique_gas_types': list(set(gas_types.tolist())),
                'concentration_stats': {
                    'min': float(concentrations.min()),
                    'max': float(concentrations.max()),
                    'mean': float(concentrations.mean()),
                    'median': float(np.median(concentrations))
                }
            }
        }
        
        logger.info("Prediction completed successfully")
        return jsonify(results)
        
    except Exception as e:
        logger.error(f"Prediction error: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    status = {
        'status': 'healthy',
        'models_trained': ('classifier' in app.config and 'regressor' in app.config)
    }
    
    if status['models_trained']:
        status['model_info'] = {
            'num_sensors': app.config.get('num_sensors'),
            'feature_columns': app.config.get('feature_columns'),
            'gas_types': app.config.get('label_encoder').classes_.tolist() if app.config.get('label_encoder') else None
        }
    
    return jsonify(status)

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=10000)
