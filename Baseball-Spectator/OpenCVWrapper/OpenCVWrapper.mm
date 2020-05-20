//
//  OpenCVWrapper.m
//  Baseball-Spectator
//
//  Created by Joey Cohen on 1/7/20.
//  Copyright © 2020 Joey Cohen. All rights reserved.
//

#import <opencv2/opencv.hpp>
#import "OpenCVWrapper.h"
#import <opencv2/imgcodecs/ios.h>
#import <UIKit/UIKit.h>
#include <chrono>
#include <ctime>
#include <cmath>
using namespace std;

//Timer to time the image processing
class Timer {
    public:
    void start() {
        m_StartTime = chrono::system_clock::now();
        m_bRunning = true;
    }
    
    void stop() {
        m_EndTime = chrono::system_clock::now();
        m_bRunning = false;
    }
    
    double elapsedMilliseconds() {
        chrono::time_point<std::chrono::system_clock> endTime;
        
        if (m_bRunning) { endTime = chrono::system_clock::now(); }
        else { endTime = m_EndTime; }
        
        return chrono::duration_cast<std::chrono::milliseconds>(endTime - m_StartTime).count();
    }
    
    double elapsedSeconds() {
        return elapsedMilliseconds() / 1000.0;
    }

    private:
    chrono::time_point<std::chrono::system_clock> m_StartTime;
    chrono::time_point<std::chrono::system_clock> m_EndTime;
    bool m_bRunning = false;
};

Timer timer;

@implementation OpenCVWrapper

+ (NSString *)openCVVersionString {
    return [NSString stringWithFormat:@"OpenCV Version %s",  CV_VERSION];
}

+ (UIImage *)processImage:(UIImage *)image expectedHomePlateAngle:(double)expectedHomePlateAngle {
    ImageProcessor processor = ImageProcessor();
    UIImage* output = processor.processImage(image, expectedHomePlateAngle);
    timer.stop();
    
    /*int nRepeats = 1000;  //use this code to get an average processing time over n repeats
    UIImage* output;
    int total = 0;
    
    for (int i = 0; i < nRepeats; i++) {
        output = processor.processImage(image, expectedHomePlateAngle);
        timer.stop();
        total += timer.elapsedMilliseconds();
    }
    
    total /= nRepeats;
    
    cout << "Processing took " << total << " milliseconds on average after " << nRepeats << " repeats." << endl;*/
    
    cout << "Processing took " << timer.elapsedMilliseconds() << " milliseconds\n";
    return output;
}






// Class to hold a contour and its basic properties
class ContourInfo {
    public:
        vector<cv::Point> contour;
        double x;
        double y;
        double width;
        double height;
    
    void printDescription(bool displayContour = false) {
        cout << "{ ";
        if (displayContour) {
            cout << "contour: " << contour << ", ";
        }
        cout << "x: " << x << ", y: " << y << ", h: " << height << ", w: " << width;
        cout << ", a: " << (height * width) << " }\n";
    }
};

bool sortByArea(const ContourInfo &struct1, const ContourInfo &struct2) {
    return ((struct1.width * struct1.height) > (struct2.width * struct2.height));
}







//Class to run the image processing
class ImageProcessor {
    public:
    cv::Scalar lowerGreen, upperGreen, lowerBrown, upperBrown, lowerDarkBrown, upperDarkBrown;
    
    ImageProcessor() {
        lowerGreen = cv::Scalar(17, 50, 20);
        upperGreen = cv::Scalar(72, 255, 242);
        
        lowerBrown = cv::Scalar(7, 80, 25);
        upperBrown = cv::Scalar(27, 255, 255);
        
        lowerDarkBrown = cv::Scalar(2, 93, 25);
        upperDarkBrown = cv::Scalar(10, 175, 150);
    }
    
    public: UIImage* processImage(UIImage* image, double expectedHomePlateAngle) {
        /*
         Main image processing routine
        
            1. Reset all central class variables to make sure the last image's processing data is cleared out
            2. Convert color from BGR to HSV
            3. Find all the pixels in the image that are a specific shade of green or brown to identify the field and dirt
            4. Find the location of the bases
            5. Find the location of the players
            6. Calculate the ideal location of each of the players' positions
            7. Assign each player an expected position
            8. RETURN each players' bottom point and their corresponding position
        */
        
        cv::Mat mat, resizedMat, hsv, greenMask, brownMask, darkBrownMask, fieldMask, erosion;
        
        UIImageToMat(image, mat);
        
        // Resize sample images to consistent height of 1080
        // TODO: Remove this after algorithm testing is complete
        int newHeight = 1080;
        double scalePercent = newHeight / image.size.height;
        int width = int(image.size.width * scalePercent);
        cv::resize(mat, resizedMat, cv::Size(width, newHeight), 0, 0, cv::INTER_AREA);
        
        timer.start();      //NOTE: Start timer here because the image scaling takes a long time and won't be performed in the final product
        
        // Convert to HSV colorspace
        cv::cvtColor(resizedMat, hsv, cv::COLOR_RGB2HSV);
        
        // Green mask
        cv::inRange(hsv, lowerGreen, cv::Scalar(72, 255, 242), greenMask);

        // Brown Mask
        cv::inRange(hsv, cv::Scalar(7, 80, 25), cv::Scalar(27, 255, 255), brownMask);
        
        // Dark Brown Mask
        cv::inRange(hsv, cv::Scalar(2, 93, 25), cv::Scalar(10, 175, 150), darkBrownMask);
        
        // Combine each mask to get a mask of the entire playing field
        cv::bitwise_or(greenMask, brownMask, fieldMask);
        cv::bitwise_or(fieldMask, darkBrownMask, fieldMask);
        
        // Get the location of the standard position of each of the fielders
        vector<cv::Point> infieldContour = getPositionLocations(greenMask, expectedHomePlateAngle);
        
        // Get the location of each of the actual players on the field
        vector<vector<cv::Point>> playerContours = getPlayerContourLocations(fieldMask);
        
        // Draw contours on image for DEBUG
        playerContours.push_back(infieldContour);
        cv::drawContours(resizedMat, playerContours, -1, cv::Scalar(255, 255, 0), 3);
        
        // Convert the Mat image to a UIImage
        UIImage *result = MatToUIImage(resizedMat);
        
        return result;
    }
    
    private: vector<cv::Point> getPositionLocations(cv::Mat greenMask, double expectedHomePlateAngle) {
        /*
         Sub-processing routine to find the location of each of the game positions

            1. Erode the image to get rid of small impurities
            2. Find all contours that are formed by the green mask
            3. Choose the contours that are between a certain bounding box area
            4. Choose the contours that have a certain (height/width) ratio, the smallest bounding box width, and an exact area above a certain threshold
                    --> the expected infield outline
            5. Fit a quadrilateral around the infield grass
            6. Compute ideal position locations based on the infield corners
            7. RETURN the image locations corresponding the positions in the following order:
                    (pitcher, home, first, second, third, shortstop, left field, center field, right field)
        */
        
        cv::Mat erosion;
        
        // Erode the image to remove impurities
        cv::erode(greenMask, erosion, getStructuringElement(cv::MORPH_RECT, cv::Size(5, 4)));
        
        // Find all contours in the image
        vector<vector<cv::Point>> contours;     // contains the array of contours
        vector<cv::Vec4i> hierarchy;            // don't actually use this
        cv::findContours(erosion, contours, hierarchy, cv::RETR_TREE, cv::CHAIN_APPROX_SIMPLE);
                
        // Only keep the contours which have a certain bounding box area
        vector<ContourInfo> infieldContours;
        
        for (vector<cv::Point> c : contours) {
            cv::Rect rect = cv::boundingRect(c);
            double area = rect.height * rect.width;
            
            if (area > 18500 and area < 2000000) {
                ContourInfo cnt;
                cnt.contour = c;
                cnt.x = rect.y + ( rect.width / 2);
                cnt.y = rect.y + ( rect.height / 2);
                cnt.width = rect.width;
                cnt.height = rect.height;
                infieldContours.push_back(cnt);
            }
        }
        
        // Sort the list of contours from biggest area to smallest
        sort(infieldContours.begin(), infieldContours.end(), sortByArea);
        
        ContourInfo infield = ContourInfo();
        infield.x = -1;
        
        for (ContourInfo cnt : infieldContours) {
            double ratio = cnt.height / cnt.width;
            
            if (ratio < 0.4 and (infield.x == -1 or cnt.width < infield.width) and cv::contourArea(cnt.contour) > 10000) {
                infield = cnt;
            }
        }
        
        if (infield.x == -1) {  }       //TODO: indicate the infield was not found
        
        vector<cv::Point> infieldHull;
        cv::convexHull(infield.contour, infieldHull);
        
        return infieldHull;
    }
    
    private: vector<vector<cv::Point>> getPlayerContourLocations(cv::Mat fieldMask) {
        /*
         Sub-processing routine to find the location of the players on the field

            1. Erode the image to get rid of small impurities
            2. Find all contours that are formed by the green and brown masks
            3. Choose the contours that are between a certain bounding box area
            4. Choose the contours that have a certain (height/width) ratio and actually are located on the field
            5. RETURN an array of the players' center pixel location
         */
        
        cv::Mat erosion;
        
        // Erode the image to remove impurities
        cv::erode(fieldMask, erosion, getStructuringElement(cv::MORPH_RECT, cv::Size(5, 5)));
        
        // Find all contours in the image
        vector<vector<cv::Point>> contours;     // contains the array of contours
        vector<cv::Vec4i> hierarchy;            // don't actually use this
        cv::findContours(erosion, contours, hierarchy, cv::RETR_TREE, cv::CHAIN_APPROX_SIMPLE);
        
        // Only keep the contours which have a certain bounding box area
        vector<ContourInfo> playerContours;
        ContourInfo field = ContourInfo();
        field.x = -1;                           // indicates that the variable is empty
        
        for (vector<cv::Point> c : contours) {
            cv::Rect rect = cv::boundingRect(c);
            double area = rect.height * rect.width;
            
            if (area > 270 and area < 2000) {
                ContourInfo cnt;
                cnt.contour = c;
                cnt.x = rect.x + (rect.width / 2);
                cnt.y = rect.y + ( rect.height / 2);
                cnt.width = rect.width;
                cnt.height = rect.height;
                playerContours.push_back(cnt);
            } else if (field.x == -1 or (field.width * field.height) < area) {
                field.contour = c;
                field.x = rect.x + (rect.width / 2);
                field.y = rect.y + ( rect.height / 2);
                field.width = rect.width;
                field.height = rect.height;
            }
        }
                
        vector<vector<cv::Point>> players;
        
        if (field.x == -1) { return players; }
        
        vector<ContourInfo> topPlayers;
        
        for (ContourInfo cnt : playerContours) {
            double ratio = cnt.height / cnt.width;
            
            if (ratio > 0.8 and ratio < 3.0) {
                topPlayers.push_back(cnt);
            }
        }
                
        if (topPlayers.size() == 0) { return players; }

        for (ContourInfo cnt : topPlayers) {
            if (isCandidatePlayerOnField(cnt, field)) {
                players.push_back(cnt.contour);
            }
        }
        
        return players;
    }
    
    private: bool isCandidatePlayerOnField(ContourInfo cnt, ContourInfo field) {
        /*
         Helper method to check if a candidate player is located on the field

             1. Check if the candidate player's center point is within the field's bounding box
                 (much faster than the opencv method, so if it isn't in the bounding box it's a quick reliable way to return false)
             2. Check if the center point is actually inside the field contour
             3. RETURN true if the result is positive
         */
        
        int fieldWidth = int(field.width / 2);
        int fieldHeight = int(field.height / 2);
        
        if (cnt.x >= field.x + fieldWidth or cnt.x <= field.x - fieldWidth or
            cnt.y >= field.y + fieldHeight or cnt.y <= field.y - fieldHeight) {
            return false;
        }
                
        double distance = cv::pointPolygonTest(field.contour, cv::Point(cnt.x, cnt.y), true);
        
        if (distance <= 0.0) {        //outside of contour or on edge of contour
            return false;
        }
        
        return true;
    }
};


@end