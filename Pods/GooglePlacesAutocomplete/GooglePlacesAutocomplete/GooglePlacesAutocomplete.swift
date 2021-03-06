//
//  GooglePlacesAutocomplete.swift
//  GooglePlacesAutocomplete
//
//  Created by Howard Wilson on 10/02/2015.
//  Copyright (c) 2015 Howard Wilson. All rights reserved.
//

import UIKit

public enum PlaceType: CustomStringConvertible {
    case All
    case Geocode
    case Address
    case Establishment
    case Regions
    case Cities
    
    public var description : String {
        switch self {
        case .All: return ""
        case .Geocode: return "geocode"
        case .Address: return "address"
        case .Establishment: return "establishment"
        case .Regions: return "(regions)"
        case .Cities: return "(cities)"
        }
    }
}

public class Place: NSObject {
    public let id: String
    public let desc: String
    public var apiKey: String?
    
    override public var description: String {
        get { return desc }
    }
    
    public init(id: String, description: String) {
        self.id = id
        self.desc = description
    }
    
    public convenience init(prediction: [String: AnyObject], apiKey: String?) {
        self.init(
            id: prediction["place_id"] as! String,
            description: prediction["description"] as! String
        )
        
        self.apiKey = apiKey
    }
    
    /**
     Call Google Place Details API to get detailed information for this place
     
     Requires that Place#apiKey be set
     
     :param: result Callback on successful completion with detailed place information
     */
    public func getDetails(result: PlaceDetails -> ()) {
        GooglePlaceDetailsRequest(place: self).request(result)
    }
}

public class PlaceDetails: CustomStringConvertible {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let raw: [String: AnyObject]
    
    public init(json: [String: AnyObject]) {
        let result = json["result"] as! [String: AnyObject]
        let geometry = result["geometry"] as! [String: AnyObject]
        let location = geometry["location"] as! [String: AnyObject]
        
        self.name = result["name"] as! String
        self.latitude = location["lat"] as! Double
        self.longitude = location["lng"] as! Double
        self.raw = json
    }
    
    public var description: String {
        return "PlaceDetails: \(name) (\(latitude), \(longitude))"
    }
}

@objc public protocol GooglePlacesAutocompleteDelegate {
    optional func placesFound(places: [Place])
    optional func placeSelected(place: Place)
    optional func placeViewClosed()
}

public var city = ""

// MARK: - GooglePlacesAutocomplete
public class GooglePlacesAutocomplete: UINavigationController {
    public var gpaViewController: GooglePlacesAutocompleteContainer!
    public var closeButton: UIBarButtonItem!
    // Proxy access to container navigationItem
    public override var navigationItem: UINavigationItem {
        get { return gpaViewController.navigationItem }
    }
    
    public var placeDelegate: GooglePlacesAutocompleteDelegate? {
        get { return gpaViewController.delegate }
        set { gpaViewController.delegate = newValue }
    }
    
    public convenience init(apiKey: String, placeType: PlaceType = .All) {
        let gpaViewController = GooglePlacesAutocompleteContainer(
            apiKey: apiKey,
            placeType: placeType
        )
        
        self.init(rootViewController: gpaViewController)
        self.gpaViewController = gpaViewController
        
        closeButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.Stop, target: self, action: "close")
        closeButton.style = UIBarButtonItemStyle.Done
        
        gpaViewController.navigationItem.leftBarButtonItem = closeButton
        gpaViewController.navigationItem.title = "Enter Address"
    }
    
    public func getCity() -> String{
        return city
    }
    
    public func setSearchText(str : String) {
        if(self.gpaViewController.searchBar != nil){
            self.gpaViewController.searchBar.text = str
            self.gpaViewController.searchBar(gpaViewController.searchBar, textDidChange: str)
            city = str
        }
    }
    
    func close() {
        placeDelegate?.placeViewClosed?()
    }
    
    public func reset() {
        gpaViewController.searchBar.text = ""
        gpaViewController.searchBar(gpaViewController.searchBar, textDidChange: "")
    }
}

// MARK: - GooglePlacesAutocompleteContainer
public class GooglePlacesAutocompleteContainer: UIViewController {
    @IBOutlet public weak var searchBar: UISearchBar!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var topConstraint: NSLayoutConstraint!
    
    var delegate: GooglePlacesAutocompleteDelegate?
    var apiKey: String?
    var places = [Place]()
    var placeType: PlaceType = .All
    
    convenience init(apiKey: String, placeType: PlaceType = .All) {
        let bundle = NSBundle(forClass: GooglePlacesAutocompleteContainer.self)
        
        self.init(nibName: "GooglePlacesAutocomplete", bundle: bundle)
        self.apiKey = apiKey
        self.placeType = placeType
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    override public func viewWillLayoutSubviews() {
        topConstraint.constant = topLayoutGuide.length
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardWasShown:", name: UIKeyboardDidShowNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardWillBeHidden:", name: UIKeyboardWillHideNotification, object: nil)
        
        searchBar.becomeFirstResponder()
        tableView.registerClass(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }
    
    func keyboardWasShown(notification: NSNotification) {
        if isViewLoaded() && view.window != nil {
            let info: Dictionary = notification.userInfo!
            let keyboardSize: CGSize = (info[UIKeyboardFrameBeginUserInfoKey]?.CGRectValue.size)!
            let contentInsets = UIEdgeInsetsMake(0.0, 0.0, keyboardSize.height, 0.0)
            
            tableView.contentInset = contentInsets;
            tableView.scrollIndicatorInsets = contentInsets;
        }
    }
    
    func keyboardWillBeHidden(notification: NSNotification) {
        if isViewLoaded() && view.window != nil {
            self.tableView.contentInset = UIEdgeInsetsZero
            self.tableView.scrollIndicatorInsets = UIEdgeInsetsZero
        }
    }
}

// MARK: - GooglePlacesAutocompleteContainer (UITableViewDataSource / UITableViewDelegate)
extension GooglePlacesAutocompleteContainer: UITableViewDataSource, UITableViewDelegate {
    public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return places.count
    }
    
    public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as! UITableViewCell
        
        // Get the corresponding candy from our candies array
        let place = self.places[indexPath.row]
        
        // Configure the cell
        cell.textLabel!.text = place.description
        cell.accessoryType = UITableViewCellAccessoryType.DisclosureIndicator
        
        return cell
    }
    
    public func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        delegate?.placeSelected?(self.places[indexPath.row])
        //    DataStruct.city = self.places[indexPath.row].desc
        self.searchBar.text = self.places[indexPath.row].desc
        city = self.places[indexPath.row].desc
        self.dismissViewControllerAnimated(true, completion: nil)
    }
}

// MARK: - GooglePlacesAutocompleteContainer (UISearchBarDelegate)
extension GooglePlacesAutocompleteContainer: UISearchBarDelegate {
    public func searchBar(searchBar: UISearchBar, textDidChange searchText: String) {
        if (searchText == "") {
            self.places = []
            city = ""
            tableView.hidden = true
        } else {
            getPlaces(searchText)
        }
    }
    
    public func searchBarSearchButtonClicked(searchBar: UISearchBar) {
        city = self.searchBar.text!
        self.dismissViewControllerAnimated(true, completion: nil)
    }
    
    /**
     Call the Google Places API and update the view with results.
     
     :param: searchString The search query
     */
    private func getPlaces(searchString: String) {
        GooglePlacesRequestHelpers.doRequest(
            "https://maps.googleapis.com/maps/api/place/autocomplete/json",
            params: [
                "input": searchString,
                "types": placeType.description,
                "key": self.apiKey!
            ]
            ) { json in
                if let predictions = json["predictions"] as? Array<[String: AnyObject]> {
                    self.places = predictions.map { (prediction: [String: AnyObject]) -> Place in
                        return Place(prediction: prediction, apiKey: self.apiKey)
                    }
                    
                    self.tableView.reloadData()
                    self.tableView.hidden = false
                    self.delegate?.placesFound?(self.places)
                }
        }
    }
}

// MARK: - GooglePlaceDetailsRequest
class GooglePlaceDetailsRequest {
    let place: Place
    
    init(place: Place) {
        self.place = place
    }
    
    func request(result: PlaceDetails -> ()) {
        GooglePlacesRequestHelpers.doRequest(
            "https://maps.googleapis.com/maps/api/place/details/json",
            params: [
                "placeid": place.id,
                "key": place.apiKey!
            ]
            ) { json in
                result(PlaceDetails(json: json as! [String: AnyObject]))
        }
    }
}

// MARK: - GooglePlacesRequestHelpers
class GooglePlacesRequestHelpers {
    /**
     Build a query string from a dictionary
     
     :param: parameters Dictionary of query string parameters
     :returns: The properly escaped query string
     */
    private class func query(parameters: [String: AnyObject]) -> String {
        var components: [(String, String)] = []
        for key in Array(parameters.keys).sort() {
            let value: AnyObject! = parameters[key]
            components += [(escape(key), escape("\(value)"))]
        }
        
        let joiner = "&"
        let elements = components.map{"\($0)=\($1)"} as [String]
        let joinedStrings = elements.joinWithSeparator(joiner)
        return joinedStrings
    }
    
    private class func escape(string: String) -> String {
        let legalURLCharactersToBeEscaped: CFStringRef = ":/?&=;+!@#$()',*"
        return CFURLCreateStringByAddingPercentEscapes(nil, string, nil, legalURLCharactersToBeEscaped, CFStringBuiltInEncodings.UTF8.rawValue) as String
    }
    
    private class func doRequest(url: String, params: [String: String], success: NSDictionary -> ()) {
        var request = NSMutableURLRequest(
            URL: NSURL(string: "\(url)?\(query(params))")!
        )
        
        var session = NSURLSession.sharedSession()
        var task = session.dataTaskWithRequest(request) { data, response, error in
            self.handleResponse(data, response: response as? NSHTTPURLResponse, error: error, success: success)
        }
        
        task.resume()
    }
    
    private class func handleResponse(data: NSData!, response: NSHTTPURLResponse!, error: NSError!, success: NSDictionary -> ()) {
        if let error = error {
            print("GooglePlaces Error: \(error.localizedDescription)")
            return
        }
        
        if response == nil {
            print("GooglePlaces Error: No response from API")
            return
        }
        
        if response.statusCode != 200 {
            print("GooglePlaces Error: Invalid status code \(response.statusCode) from API")
            return
        }
        
        var serializationError: NSError?
        var json: NSDictionary
        do {
            json = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableContainers) as! NSDictionary
            
            print(json)
            
            if let error = serializationError {
                print("GooglePlaces Error: \(error.localizedDescription)")
                return
            }
            
            if let status = json["status"] as? String {
                if status != "OK" {
                    print("GooglePlaces API Error: \(status)")
                    return
                }
            }
            
            // Perform table updates on UI thread
            dispatch_async(dispatch_get_main_queue(), {
                UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                
                success(json)
            })
        }catch{
            print("Error")
        }
        
        
    }
}
